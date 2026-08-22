// 本地 OpenAI 兼容 API 服务器（创新点）
// 用 @ohos.net.socket 的 TCPSocketServer 手写 HTTP/1.1，提供 /v1/chat/completions 和 /v1/models
// 供鸿蒙电脑上的智能体/第三方客户端接本地模型推理
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'ApiServer';

export interface ApiServerConfig {
  enabled: boolean;
  host: string;    // 监听地址：127.0.0.1 仅本机 / 0.0.0.0 局域网
  port: number;    // 端口，默认 8080
}

// OpenAI 兼容的 chat completion 请求体（只取必需字段）
interface ChatMessage {
  role: string;
  content: string;
}

interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  stream?: boolean;
  temperature?: number;
  max_tokens?: number;
}

interface ModelEntry {
  id: string;
  object: string;
  owned_by: string;
}

interface ChatChoice {
  index: number;
  message: ChatMessage;
  finish_reason: string;
}

interface UsageInfo {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

interface ChatCompletionResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: ChatChoice[];
  usage: UsageInfo;
}

export class ApiServer {
  private tcpServer: socket.TCPSocketServer | null = null;
  private config: ApiServerConfig;
  // 推理回调：由 Index 注入（调用 mnnllm.submitSync）
  private inference: ((prompt: string) => Promise<string>) | null = null;
  // 访问令牌（可选）：空串 = 不鉴权
  private authToken: string = '';

  constructor(config: ApiServerConfig) {
    this.config = config;
  }

  setInference(fn: (prompt: string) => Promise<string>): void {
    this.inference = fn;
  }

  setAuthToken(token: string): void {
    this.authToken = token;
  }

  async start(): Promise<boolean> {
    if (this.tcpServer) {
      return true;   // 已在运行
    }
    try {
      const server = socket.constructTCPSocketServerInstance();
      await server.listen({ address: this.config.host, port: this.config.port, family: 1 });
      server.on('connect', (conn: socket.TCPSocketConnection) => {
        this.handleConnection(conn);
      });
      server.on('error', (err: Error) => {
        hilog.error(0x0000, TAG, 'server error: %{public}s', err.message);
      });
      this.tcpServer = server;
      hilog.info(0x0000, TAG, 'API server started at %{public}s:%{public}d', this.config.host, this.config.port);
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'API server start failed: %{public}s', (e as Error).message);
      return false;
    }
  }

  async stop(): Promise<void> {
    if (this.tcpServer) {
      try {
        await this.tcpServer.close();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'server close: %{public}s', (e as Error).message);
      }
      this.tcpServer = null;
      hilog.info(0x0000, TAG, 'API server stopped');
    }
  }

  isRunning(): boolean {
    return this.tcpServer !== null;
  }

  // 处理单个客户端连接：读请求 → 路由 → 回响应
  private handleConnection(conn: socket.TCPSocketConnection): void {
    const byteBuffer: number[] = [];   // 字节累积（不是字符串！Content-Length 是字节数）
    hilog.info(0x0000, TAG, 'connection accepted');
    conn.on('message', (data: socket.SocketMessageInfo) => {
      const chunk = data.message as ArrayBuffer;
      const bytes = new Uint8Array(chunk);
      for (let i = 0; i < bytes.length; i++) {
        byteBuffer.push(bytes[i]);
      }
      hilog.info(0x0000, TAG, 'received %{public}d bytes, total=%{public}d', bytes.length, byteBuffer.length);
      // 在字节数组里找 \r\n\r\n（13,10,13,10）
      const headerEnd = this.findBytes(byteBuffer, [13, 10, 13, 10]);
      if (headerEnd < 0) {
        return;
      }
      // 解析 header（字节 → 字符串）
      const headerStr = this.bytesToString(byteBuffer.slice(0, headerEnd));
      const contentLenMatch = headerStr.match(/Content-Length:\s*(\d+)/i);
      let bodyLen = 0;
      if (contentLenMatch) {
        bodyLen = parseInt(contentLenMatch[1], 10);
      }
      const totalLen = headerEnd + 4 + bodyLen;   // 字节数
      if (byteBuffer.length < totalLen) {
        return;   // body 未收完，继续等
      }
      // 提取完整请求（字节 → 字符串），剩余留在 buffer
      const rawRequest = this.bytesToString(byteBuffer.slice(0, totalLen));
      byteBuffer.splice(0, totalLen);

      this.handleRequest(rawRequest).then((response: string) => {
        conn.send({ data: response }).catch((e: Error) => {
          hilog.warn(0x0000, TAG, 'send response failed: %{public}s', e.message);
        });
        if (!headerStr.toLowerCase().includes('connection: keep-alive')) {
          conn.close().catch(() => {});
        }
      }).catch((e: Error) => {
        const errResp = this.httpResponse(500, 'application/json', JSON.stringify({ error: e.message }));
        conn.send({ data: errResp }).catch(() => {});
        conn.close().catch(() => {});
      });
    });
    conn.on('close', () => {
      // 连接关闭，清理
    });
  }

  // 在字节数组里找子序列，返回起始下标（未找到返回 -1）
  private findBytes(haystack: number[], needle: number[]): number {
    for (let i = 0; i <= haystack.length - needle.length; i++) {
      let match = true;
      for (let j = 0; j < needle.length; j++) {
        if (haystack[i + j] !== needle[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        return i;
      }
    }
    return -1;
  }

  private bytesToString(bytes: number[]): string {
    const decoder = new util.TextDecoder();
    return decoder.decode(new Uint8Array(bytes));
  }

  private arrayBufferToString(buf: ArrayBuffer): string {
    const decoder = new util.TextDecoder();
    return decoder.decode(new Uint8Array(buf));
  }

  // 路由 + 处理
  private async handleRequest(raw: string): Promise<string> {
    const firstLine = raw.split('\r\n')[0];
    hilog.info(0x0000, TAG, 'handleRequest: %{public}s', firstLine);
    const parts = firstLine.split(' ');
    const method = parts[0];
    const path = parts[1];

    // 鉴权（可选）
    if (this.authToken.length > 0) {
      const authMatch = raw.match(/Authorization:\s*Bearer\s+(\S+)/i);
      if (!authMatch || authMatch[1] !== this.authToken) {
        return this.httpResponse(401, 'application/json', JSON.stringify({ error: 'unauthorized' }));
      }
    }

    // 路由
    if (method === 'GET' && path === '/v1/models') {
      const entry: ModelEntry = { id: 'duanyu-local', object: 'model', owned_by: 'duanyu' };
      const body = JSON.stringify({ object: 'list', data: [entry] });
      return this.httpResponse(200, 'application/json', body);
    }

    if (method === 'POST' && path === '/v1/chat/completions') {
      const headerEnd = raw.indexOf('\r\n\r\n');
      const bodyStr = raw.substring(headerEnd + 4);
      return await this.handleChatCompletion(bodyStr);
    }

    if (method === 'GET' && (path === '/health' || path === '/')) {
      return this.httpResponse(200, 'application/json', JSON.stringify({ status: 'ok', model: 'duanyu-local' }));
    }

    return this.httpResponse(404, 'application/json', JSON.stringify({ error: 'not found: ' + path }));
  }

  // 处理 chat completions
  private async handleChatCompletion(bodyStr: string): Promise<string> {
    let req: ChatCompletionRequest;
    try {
      req = JSON.parse(bodyStr) as ChatCompletionRequest;
    } catch (e) {
      return this.httpResponse(400, 'application/json', JSON.stringify({ error: 'invalid JSON body' }));
    }
    if (!req.messages || req.messages.length === 0) {
      return this.httpResponse(400, 'application/json', JSON.stringify({ error: 'messages required' }));
    }
    if (!this.inference) {
      return this.httpResponse(503, 'application/json', JSON.stringify({ error: 'engine not ready' }));
    }
    // 取最后一条 user 消息作为 prompt（简化：多轮由 C++ 历史管理）
    const lastUser = req.messages.filter((m) => m.role === 'user').pop();
    const prompt = lastUser ? lastUser.content : req.messages[req.messages.length - 1].content;
    try {
      const reply = await this.inference(prompt);
      const msg: ChatMessage = { role: 'assistant', content: reply };
      const choice: ChatChoice = { index: 0, message: msg, finish_reason: 'stop' };
      const usage: UsageInfo = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };
      const respObj: ChatCompletionResponse = {
        id: 'chatcmpl-' + Date.now(),
        object: 'chat.completion',
        created: Math.floor(Date.now() / 1000),
        model: req.model || 'duanyu-local',
        choices: [choice],
        usage: usage
      };
      return this.httpResponse(200, 'application/json', JSON.stringify(respObj));
    } catch (e) {
      return this.httpResponse(500, 'application/json', JSON.stringify({ error: (e as Error).message }));
    }
  }

  // 构造 HTTP 响应
  private httpResponse(code: number, contentType: string, body: string): string {
    const reasonMap: Record<number, string> = {
      200: 'OK', 400: 'Bad Request', 401: 'Unauthorized', 404: 'Not Found',
      500: 'Internal Server Error', 503: 'Service Unavailable'
    };
    const reason = reasonMap[code] || 'Unknown';
    const bodyBytes = this.stringToUtf8Bytes(body).length;
    return 'HTTP/1.1 ' + code + ' ' + reason + '\r\n' +
      'Content-Type: ' + contentType + '\r\n' +
      'Content-Length: ' + bodyBytes + '\r\n' +
      'Access-Control-Allow-Origin: *\r\n' +
      'Connection: close\r\n' +
      '\r\n' + body;
  }

  private stringToUtf8Bytes(s: string): Uint8Array {
    const bytes: number[] = [];
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
      } else if (code >= 0xD800 && code <= 0xDBFF) {
        // 代理对（emoji 等）
        const next = s.charCodeAt(i + 1);
        const cp = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00);
        i++;
        bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
      } else {
        bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
    }
    return new Uint8Array(bytes);
  }
}
