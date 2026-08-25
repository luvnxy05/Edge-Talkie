// 端语——本地大模型对话（M2: 多轮上下文 + 会话持久化 + 推理统计）
import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { router, window } from '@kit.ArkUI';
import { ApiServer } from '../utils/ApiServer';
import mnnllm from 'libmnnllm.so';

const TAG: string = 'MnnChat';
// 模型直连魔搭社区（ModelScope）下载：resolve 端点 302 重定向到 CDN，再对 CDN 分段下载
const MODELSCOPE_RESOLVE: string = 'https://modelscope.cn/models/MNN';

// 模型白名单（ModelScope MNN 官方组织全部 17 个 4-bit MNN 模型，2026-08 探测）
interface ModelSpec {
  id: string;            // 目录名 = ModelScope 模型 ID
  displayName: string;   // 显示名
  files: string[];       // 必需文件清单（README.md/.gitattributes 除外）
  weightMinBytes: number; // weight 文件最小字节数（防残片误判）
  desc: string;          // 描述
}

const MB: number = 1024 * 1024;

const MODEL_LIST: ModelSpec[] = [
  // ---- Qwen3 系列（支持思考链）----
  { id: 'Qwen3-0.6B-MNN', displayName: 'Qwen3 0.6B', files: ['config.json', 'configuration.json', 'llm_config.json', 'llm.mnn', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 405 * MB, desc: '最快 · 手机/PC 皆可' },
  { id: 'Qwen3-1.7B-MNN', displayName: 'Qwen3 1.7B', files: ['config.json', 'configuration.json', 'llm_config.json', 'llm.mnn', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 1108 * MB, desc: '均衡 · 约 1.2GB' },
  { id: 'Qwen3-4B-MNN', displayName: 'Qwen3 4B', files: ['config.json', 'configuration.json', 'llm_config.json', 'llm.mnn', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 2439 * MB, desc: '更强 · 需 4GB+ 内存' },
  { id: 'Qwen3-8B-MNN', displayName: 'Qwen3 8B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 3833 * MB, desc: '强 · 需 8GB+ 内存' },
  { id: 'Qwen3-14B-MNN', displayName: 'Qwen3 14B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 7085 * MB, desc: '很强 · 需 16GB+ 内存' },
  { id: 'Qwen3-32B-MNN', displayName: 'Qwen3 32B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 16196 * MB, desc: '最强 · 需 32GB+ 内存' },
  { id: 'Qwen3-30B-A3B-MNN', displayName: 'Qwen3 30B-A3B (MoE)', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 15301 * MB, desc: 'MoE · 需 32GB+ 内存' },
  // ---- Qwen2.5 系列（无思考链）----
  { id: 'Qwen2.5-0.5B-Instruct-MNN', displayName: 'Qwen2.5 0.5B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 250 * MB, desc: '最小 · 能力最弱' },
  { id: 'Qwen2.5-1.5B-Instruct-MNN', displayName: 'Qwen2.5 1.5B', files: ['config.json', 'configuration.json', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 781 * MB, desc: '均衡 · 无思考链' },
  { id: 'Qwen2.5-3B-Instruct-MNN', displayName: 'Qwen2.5 3B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 1562 * MB, desc: '较强 · 需 4GB+ 内存' },
  { id: 'Qwen2.5-7B-Instruct-MNN', displayName: 'Qwen2.5 7B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 3580 * MB, desc: '强 · 需 8GB+ 内存' },
  // ---- Qwen1.5 系列（旧版，无思考链）----
  { id: 'Qwen1.5-0.5B-Chat-MNN', displayName: 'Qwen1.5 0.5B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 235 * MB, desc: '最小 · 旧版' },
  { id: 'Qwen1.5-1.8B-Chat-MNN', displayName: 'Qwen1.5 1.8B', files: ['config.json', 'configuration.json', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 772 * MB, desc: '均衡 · 旧版' },
  { id: 'Qwen1.5-4B-Chat-MNN', displayName: 'Qwen1.5 4B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 1803 * MB, desc: '较强 · 旧版 · 需 4GB+' },
  { id: 'Qwen1.5-7B-Chat-MNN', displayName: 'Qwen1.5 7B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 3595 * MB, desc: '强 · 旧版 · 需 8GB+' },
  // ---- 其他 ----
  { id: 'glm-4-9b-chat-MNN', displayName: 'GLM-4 9B', files: ['config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'llm.mnn', 'llm.mnn.json', 'tokenizer.txt', 'llm.mnn.weight'], weightMinBytes: 4444 * MB, desc: '智谱 · 需 10GB+ 内存' },
  { id: 'Baichuan2-7B-Chat-MNN', displayName: 'Baichuan2 7B', files: ['baichuan2-7b-int4.mnn', 'baichuan2-7b-int4.mnn.weight', 'config.json', 'configuration.json', 'embeddings_bf16.bin', 'llm_config.json', 'tokenizer.txt'], weightMinBytes: 3162 * MB, desc: '百川 · 需 8GB+ 内存' }
];

// 持久化会话结构（与原生多轮 history 独立：UI 层保存完整消息用于展示/恢复）
interface PersistMessage {
  role: string;
  content: string;
  time: number;
}

interface PersistSession {
  id: string;
  title: string;
  updatedAt: number;
  messages: PersistMessage[];
}

// 正文分段：代码块 / 标题 / 普通文本（加粗用 ** 标记）
interface Segment {
  isCode: boolean;
  isHeading: boolean;
  level: number;     // 标题级别 1/2/3
  content: string;
}

// 行内加粗片段
interface InlineSeg {
  bold: boolean;
  text: string;
}

function splitCodeBlocks(md: string): Segment[] {
  const segs: Segment[] = [];
  const parts = md.split(/```[\s\S]*?```/);
  const codes = md.match(/```[\s\S]*?```/g) || [];
  for (let i = 0; i < parts.length; i++) {
    // 文本部分按行拆，识别标题行（# ## ###）
    const lines = parts[i].split('\n');
    for (const line of lines) {
      if (line.trim().length === 0) {
        continue;
      }
      const hm = line.match(/^(#{1,3})\s+(.+)$/);
      if (hm) {
        segs.push({ isCode: false, isHeading: true, level: hm[1].length, content: hm[2].trim() });
      } else {
        segs.push({ isCode: false, isHeading: false, level: 0, content: line });
      }
    }
    if (i < codes.length) {
      const code = codes[i].replace(/^```[^\n]*\n?/, '').replace(/```$/, '');
      segs.push({ isCode: true, isHeading: false, level: 0, content: code });
    }
  }
  return segs;
}

// 拆分行内加粗：**text** → [{bold:false,text}, {bold:true,text}, ...]
function splitBold(line: string): InlineSeg[] {
  const segs: InlineSeg[] = [];
  const parts = line.split(/\*\*([^*]+)\*\*/);
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0) {
      continue;
    }
    segs.push({ bold: (i % 2 === 1), text: parts[i] });
  }
  return segs;
}

// 消息必须用 @Observed class（不是 interface）——否则回调里改 msg.content 不触发 UI 刷新
@Observed
class ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  think: string;      // 思考部分（<think>...</think> 内）
  body: string;       // 正文部分（think 标签外）
  thinkCollapsed: boolean;  // 思考是否收起
  streaming: boolean;       // 是否正在流式生成中
  stats: string;            // 推理统计文案（如"输入12 · 输出345 · 12.3 tok/s"）
  constructor(role: 'user' | 'assistant', content: string) {
    this.role = role;
    this.content = content;
    this.think = '';
    this.body = '';
    this.thinkCollapsed = true;   // 默认收起思考
    this.streaming = false;
    this.stats = '';
    this.parseThink();
  }

  // 解析 <think>...</think>，拆出思考与正文
  parseThink(): void {
    const m = this.content.match(/<think>([\s\S]*?)<\/think>([\s\S]*)/);
    if (m) {
      this.think = m[1].trim();
      this.body = m[2].trim();
      // 生成中思考默认展开，生成完（外部设 streaming=false）再收起
      this.thinkCollapsed = !this.streaming;
    } else {
      this.think = '';
      this.body = this.content;
    }
  }

  // 追加内容后重新解析（流式时逐段调用）
  append(chunk: string): void {
    this.content += chunk;
    this.parseThink();
  }
}

// 气泡子组件：@ObjectLink 观察 @Observed 对象，content 变化即时刷新
@Component
struct MessageBubble {
  @ObjectLink msg: ChatMessage;
  @Prop isDark: boolean = false;

  build() {
    Row() {
      if (this.msg.role === 'user') {
        Blank()
        Column({ space: 4 }) {
          Text(this.msg.content)
            .fontSize(15)
            .fontColor(Color.White)
            .lineHeight(22)
        }
        .padding(10)
        .backgroundColor('#0A59F7')
        .borderRadius(10)
        .constraintSize({ maxWidth: '75%' })
      } else {
        Column({ space: 4 }) {
          // 思考部分：浅灰 + 可折叠（宽度跟随内容，不用 width('100%') 撑满）
          if (this.msg.think.length > 0) {
            Column({ space: 4 }) {
              Text(this.msg.thinkCollapsed ? '思考过程 ▸' : '思考过程 ▾')
                .fontSize(12)
                .fontColor(this.isDark ? '#8A8A8A' : '#999999')
                .onClick(() => {
                  this.msg.thinkCollapsed = !this.msg.thinkCollapsed;
                })
              if (!this.msg.thinkCollapsed) {
                Text(this.msg.think)
                  .fontSize(13)
                  .fontColor(this.isDark ? '#8A8A8A' : '#999999')
                  .lineHeight(20)
              }
            }
            .padding(8)
            .backgroundColor(this.isDark ? '#333333' : '#F7F7F7')
            .borderRadius(8)
            .alignItems(HorizontalAlign.Start)
          }
          // 正文：流式时简单 Text（快，避免 ForEach 频繁重建卡顿），完成后分段渲染代码块
          if (this.msg.streaming) {
            Text(this.msg.body.length > 0 ? this.msg.body : this.msg.content)
              .fontSize(15)
              .fontColor(this.isDark ? '#E0E0E0' : '#222222')
              .lineHeight(22)
          } else {
            ForEach(splitCodeBlocks(this.msg.body.length > 0 ? this.msg.body : this.msg.content), (seg: Segment) => {
              if (seg.isCode) {
                Text(seg.content)
                  .fontSize(13)
                  .fontColor(this.isDark ? '#D0D0D0' : '#333333')
                  .fontFamily('monospace')
                  .backgroundColor(this.isDark ? '#1E1E1E' : '#F5F5F5')
                  .padding(8)
                  .borderRadius(6)
                  .wordBreak(WordBreak.BREAK_ALL)
                  .constraintSize({ maxWidth: '100%' })
                  .margin({ top: 2, bottom: 2 })
              } else if (seg.isHeading) {
                Text(seg.content)
                  .fontSize(seg.level === 1 ? 20 : (seg.level === 2 ? 18 : 16))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isDark ? '#E0E0E0' : '#222222')
                  .margin({ top: 8, bottom: 2 })
              } else {
                Text() {
                  ForEach(splitBold(seg.content), (b: InlineSeg) => {
                    Span(b.text)
                      .fontWeight(b.bold ? FontWeight.Bold : FontWeight.Normal)
                  }, (b: InlineSeg, idx: number) => idx.toString() + (b.bold ? 'b' : 'n'))
                }
                .fontSize(15)
                .fontColor(this.isDark ? '#E0E0E0' : '#222222')
                .lineHeight(22)
              }
            }, (seg: Segment, index: number) => index.toString() + (seg.isCode ? 'c' : (seg.isHeading ? 'h' : 't')))
          }
          // 推理统计
          if (this.msg.stats.length > 0) {
            Text(this.msg.stats)
              .fontSize(10)
              .fontColor(this.isDark ? '#666666' : '#bbbbbb')
              .margin({ top: 2 })
          }
        }
        .padding(10)
        .backgroundColor(this.isDark ? '#2A2A2A' : '#F0F0F0')
        .borderRadius(10)
        .constraintSize({ maxWidth: '75%' })
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

@Entry
@Component
struct Index {
  @State statusText: string = '引擎未加载';
  @State modelName: string = 'Qwen3-0.6B-MNN';
  @State aiLabelVisible: boolean = true;
  @State inputText: string = '';
  @State messages: ChatMessage[] = [
    new ChatMessage('assistant', '你好，我是端语——运行在你设备上的本地对话助手。输入问题开始聊天。')
  ];
  @State isGenerating: boolean = false;
  @State stopping: boolean = false;             // 已点暂停、等待 prefill 结束
  @State engineReady: boolean = false;
  @State sessions: PersistSession[] = [];      // 历史会话列表
  @State currentSessionId: string = '';        // 当前会话 id
  @State showSidebar: boolean = false;         // 侧边栏显示
  @State showSettings: boolean = false;        // 参数设置面板
  @State temperature: number = 0.6;            // 温度（0.1~1.5）
  @State thinkingEnabled: boolean = true;       // 思考模式开关
  @State isDark: boolean = false;               // 深色模式
  @State apiEnabled: boolean = false;           // API 服务开关
  @State apiStatus: string = '未启动';          // API 服务状态
  @State apiToken: string = '';                 // API 访问令牌（空 = 不鉴权）
  @State showModelManager: boolean = false;      // 模型管理面板
  @State currentModelId: string = 'Qwen3-0.6B-MNN';  // 当前模型
  @State downloadedModels: string[] = [];         // 已下载模型 id 列表
  @State downloadingModel: string = '';           // 正在下载的模型 id
  @State downloadProgress: number = 0;            // 当前文件下载进度 0-100
  @State downloadFileName: string = '';           // 当前下载的文件名
  @State downloadPercent: number = 0;             // 当前文件百分比（显示用）
  private apiServer: ApiServer = new ApiServer({ enabled: false, host: '0.0.0.0', port: 8080 });
  private scroller: Scroller = new Scroller();
  private context = getContext(this) as common.UIAbilityContext;
  private llmSession: Object | null = null;
  private modelDir: string = '';

  aboutToAppear(): void {
    hilog.info(0x0000, TAG, '端语 launched');
    this.loadSessions();
    this.refreshDownloadedModels();
    this.initEngine();
  }

  aboutToDisappear(): void {
    if (this.llmSession) {
      mnnllm.release(this.llmSession);
      this.llmSession = null;
    }
  }

  // 判断某个模型是否已完整下载（防残片误判）
  private isModelDownloaded(spec: ModelSpec): boolean {
    const dir: string = this.context.filesDir + '/models/' + spec.id;
    for (const f of spec.files) {
      const p: string = dir + '/' + f;
      try {
        const st: fs.Stat = fs.statSync(p);
        if (st.size <= 0) {
          return false;
        }
        // weight 文件必须达到模型专属的最小字节数（防残片）；文件名含 weight（llm.mnn.weight / baichuan2-7b-int4.mnn.weight 都命中）
        if (f.includes('weight') && st.size < spec.weightMinBytes) {
          return false;
        }
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  // 刷新已下载模型列表
  private refreshDownloadedModels(): void {
    const list: string[] = [];
    for (const spec of MODEL_LIST) {
      if (this.isModelDownloaded(spec)) {
        list.push(spec.id);
      }
    }
    this.downloadedModels = list;
  }

  private async ensureModel(modelId: string): Promise<string> {
    const spec = MODEL_LIST.find((m: ModelSpec) => m.id === modelId);
    if (!spec) {
      throw new Error('unknown model: ' + modelId);
    }
    // 应用沙箱文件目录（应用自己有完整读写权限）
    const baseDir: string = this.context.filesDir;
    const dir: string = baseDir + '/models/' + modelId;
    try {
      fs.mkdirSync(dir, true);
      hilog.info(0x0000, TAG, 'mkdir ok: %{public}s', dir);
    } catch (e) {
      // 目录已存在属正常（鸿蒙 mkdirSync 对已存在目录抛 File exists）
      hilog.info(0x0000, TAG, 'mkdir exists (ok): %{public}s', dir);
    }
    // 已完整下载则直接返回
    if (this.isModelDownloaded(spec)) {
      hilog.info(0x0000, TAG, 'model %{public}s already exists in sandbox', modelId);
      return dir;
    }
    // 下载全部文件
    this.downloadingModel = modelId;
    for (const f of spec.files) {
      this.statusText = '下载 ' + spec.displayName + ' ' + f + '…';
      this.downloadFileName = f;
      this.downloadPercent = 0;
      await this.downloadFile(modelId, f, dir + '/' + f, (pct: number) => {
        this.downloadPercent = pct;
      });
    }
    this.downloadingModel = '';
    this.downloadFileName = '';
    this.downloadPercent = 0;
    hilog.info(0x0000, TAG, 'model %{public}s files downloaded', modelId);
    return dir;
  }

  // 解析 ModelScope resolve 端点的 CDN 直链（302 Location 头）
  private async resolveCdnUrl(modelId: string, fileName: string): Promise<string> {
    const url = MODELSCOPE_RESOLVE + '/' + modelId + '/resolve/master/' + fileName;
    const httpReq = http.createHttp();
    try {
      const resp = await httpReq.request(url, {
        method: http.RequestMethod.GET,
        maxRedirects: 0,   // 不跟随 302，拿到 Location 头
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 30000
      });
      const loc: string = resp.header['location'] as string;
      if (loc && loc.length > 0) {
        return loc;
      }
      return url;
    } catch (e) {
      return url;   // 拿不到 Location（抛 2300047 等）就回退原 URL
    } finally {
      httpReq.destroy();
    }
  }

  private async downloadFile(modelId: string, fileName: string, dest: string, onProgress?: (percent: number) => void): Promise<void> {
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const isWeight: boolean = fileName.includes('weight');
      if (!isWeight) {
        // 小文件：resolve 端点直接 200 返回完整内容，不发 Range（主站对 Range 有 bug：返回错误 Content-Length 导致 partial file）
        const url = MODELSCOPE_RESOLVE + '/' + modelId + '/resolve/master/' + fileName;
        hilog.info(0x0000, TAG, 'downloading %{public}s', fileName);
        const httpReq = http.createHttp();
        try {
          const resp = await httpReq.request(url, {
            method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            readTimeout: 60000
          });
          const code: number = resp.responseCode as number;
          if (code !== 200) {
            throw new Error('HTTP ' + code + ' for ' + fileName);
          }
          const buf: ArrayBuffer = resp.result as ArrayBuffer;
          fs.writeSync(file.fd, buf);
          if (onProgress) {
            onProgress(100);
          }
        } finally {
          httpReq.destroy();
        }
        hilog.info(0x0000, TAG, 'downloaded %{public}s', fileName);
      } else {
        // weight 大文件：resolve 拿 CDN 直链（支持 Range），再 32MB 分段下载
        const CHUNK: number = 32 * 1024 * 1024;
        const cdnUrl = await this.resolveCdnUrl(modelId, fileName);
        let offset: number = 0;
        let totalSize: number = -1;
        hilog.info(0x0000, TAG, 'downloading %{public}s (cdn)', fileName);
        while (true) {
          const end: number = offset + CHUNK - 1;
          const httpReq = http.createHttp();
          let resp: http.HttpResponse;
          try {
            resp = await httpReq.request(cdnUrl, {
              method: http.RequestMethod.GET,
              header: { 'Range': 'bytes=' + offset + '-' + end.toString() },
              expectDataType: http.HttpDataType.ARRAY_BUFFER,
              readTimeout: 120000
            });
          } finally {
            httpReq.destroy();
          }
          const code: number = resp.responseCode as number;
          if (code !== 206 && code !== 200) {
            throw new Error('HTTP ' + code + ' for ' + fileName);
          }
          if (totalSize < 0 && resp.header) {
            const cr: string = resp.header['content-range'] as string;
            if (cr) {
              const m = cr.match(/\/(\d+)/);
              if (m) {
                totalSize = parseInt(m[1], 10);
              }
            }
            if (totalSize < 0) {
              const cl: string = resp.header['content-length'] as string;
              if (cl) {
                totalSize = parseInt(cl, 10);
              }
            }
          }
          const buf: ArrayBuffer = resp.result as ArrayBuffer;
          if (buf.byteLength <= 0) {
            break;
          }
          fs.writeSync(file.fd, buf);
          offset += buf.byteLength;
          if (onProgress && totalSize > 0) {
            const pct = Math.min(100, Math.round(offset * 100 / totalSize));
            onProgress(pct);
          }
          if (buf.byteLength < CHUNK) {
            break;
          }
          await new Promise<void>((resolve) => setTimeout(resolve, 50));
        }
        hilog.info(0x0000, TAG, 'downloaded %{public}s total=%{public}d bytes', fileName, offset);
      }
      fs.closeSync(file);
    } catch (e) {
      fs.closeSync(file);
      hilog.error(0x0000, TAG, 'download failed %{public}s: %{public}s', fileName, (e as Error).message);
      throw new Error('download failed: ' + (e as Error).message);
    }
  }

  initEngine(): void {
    this.statusText = '检查模型…';
    this.ensureModel(this.currentModelId).then((dir: string) => {
      this.modelDir = dir;
      this.statusText = '加载模型中…';
      hilog.info(0x0000, TAG, 'loading engine from %{public}s', dir);
      setTimeout(() => {
        try {
          const session: Object = mnnllm.init(dir);
          this.llmSession = session;
          this.engineReady = true;
          this.statusText = '引擎已就绪';
          this.refreshDownloadedModels();
          hilog.info(0x0000, TAG, 'Engine loaded OK');
        } catch (e) {
          hilog.error(0x0000, TAG, 'Engine load failed: %{public}s, msg=%{public}s', JSON.stringify(e), (e as Error).message);
          this.statusText = '引擎加载失败';
          this.engineReady = false;
        }
      }, 100);
    }).catch((e: Error) => {
      hilog.error(0x0000, TAG, 'model prepare failed: %{public}s', e.message);
      this.statusText = '模型准备失败：' + e.message;
      this.engineReady = false;
    });
  }

  // 切换模型：destroy 旧引擎 + init 新引擎
  switchModel(modelId: string): void {
    if (modelId === this.currentModelId && this.engineReady) {
      this.showModelManager = false;
      return;   // 已是当前模型
    }
    this.currentModelId = modelId;
    this.engineReady = false;
    // 释放旧引擎
    if (this.llmSession) {
      mnnllm.release(this.llmSession);
      this.llmSession = null;
    }
    this.statusText = '切换模型中…';
    this.initEngine();
    this.showModelManager = false;
  }

  // 删除模型（仅删沙箱文件，不删当前使用的）
  deleteModel(modelId: string): void {
    if (modelId === this.currentModelId) {
      hilog.warn(0x0000, TAG, 'cannot delete current model');
      return;
    }
    const dir: string = this.context.filesDir + '/models/' + modelId;
    try {
      // 逐个删文件
      const spec = MODEL_LIST.find((m: ModelSpec) => m.id === modelId);
      if (spec) {
        for (const f of spec.files) {
          try {
            fs.unlinkSync(dir + '/' + f);
          } catch (e) {
            // 文件不存在属正常
          }
        }
      }
      hilog.info(0x0000, TAG, 'deleted model %{public}s', modelId);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'delete model failed: %{public}s', (e as Error).message);
    }
    this.refreshDownloadedModels();
  }

  sendMessage(): void {
    const text: string = this.inputText.trim();
    if (!text || this.isGenerating) {
      return;
    }
    // 用户消息上屏
    this.messages.push(new ChatMessage('user', text));
    this.inputText = '';
    this.isGenerating = true;
    this.statusText = '推理中…';
    this.scroller.scrollEdge(Edge.Bottom);

    if (this.engineReady && this.llmSession) {
      // 真实推理：NAPI submit 启动后台推理 + setInterval 轮询 poll() 取流式内容
      const assistantMsg = new ChatMessage('assistant', '');
      assistantMsg.streaming = true;   // 生成中：思考展开显示
      this.messages.push(assistantMsg);
      try {
        mnnllm.submit(this.llmSession, text);
        // 轮询：30ms 取一次；submit 后立即 poll 一次，避免高速推理下首批累积一大块
        let pollTimer: number = 0;
        const doPoll = (): void => {
          try {
            const r = mnnllm.poll(this.llmSession!);
            if (r.chunk.length > 0) {
              assistantMsg.append(r.chunk);
              this.scroller.scrollEdge(Edge.Bottom);
            }
            if (r.error.length > 0) {
              clearInterval(pollTimer);
              assistantMsg.content += '\n（推理失败：' + r.error + '）';
              assistantMsg.parseThink();
              this.finishGenerating(assistantMsg);
            }
            if (r.done) {
              clearInterval(pollTimer);
              assistantMsg.stats = '输入' + r.promptTokens + ' · 输出' + r.outputTokens + ' · ' + r.tokPerSec.toFixed(1) + ' tok/s';
              this.finishGenerating(assistantMsg);
            }
          } catch (e) {
            clearInterval(pollTimer);
            this.finishGenerating(assistantMsg);
          }
        };
        doPoll();
        pollTimer = setInterval(doPoll, 30);
      } catch (e) {
        hilog.error(0x0000, TAG, 'submit failed: %{public}s', JSON.stringify(e));
        assistantMsg.content = '（推理失败：' + JSON.stringify(e) + '）';
        assistantMsg.parseThink();
        this.finishGenerating(assistantMsg);
      }
    } else {
      // mock 回退
      setTimeout(() => {
        this.messages.push(new ChatMessage('assistant', '（模型未加载，占位回复）收到："' + text + '"'));
        this.isGenerating = false;
        this.statusText = this.engineReady ? '引擎已就绪' : '引擎未加载';
        this.scroller.scrollEdge(Edge.Bottom);
      }, 500);
    }
  }

  // 生成结束：收起思考 + 复位状态
  finishGenerating(msg: ChatMessage): void {
    msg.streaming = false;
    msg.parseThink();   // 收起思考（thinkCollapsed = !streaming = true）
    this.isGenerating = false;
    this.stopping = false;
    this.statusText = '引擎已就绪';
    this.scroller.scrollEdge(Edge.Bottom);
    this.saveCurrentSession();   // 落盘
  }

  // 停止生成：置位停止标志，streambuf flush 抛异常中断 response()
  stopGenerating(): void {
    if (this.llmSession && this.isGenerating && !this.stopping) {
      this.stopping = true;   // 立即反馈：按钮变"停止中"，不等 prefill 完成
      mnnllm.stop(this.llmSession);
      this.statusText = '正在停止…';
      hilog.info(0x0000, TAG, 'stop requested');
    }
  }

  // ============ 会话持久化 ============
  private getPrefStore(): preferences.Preferences {
    return preferences.getPreferencesSync(this.context, { name: 'chat_sessions' });
  }

  loadSessions(): void {
    try {
      const store = this.getPrefStore();
      const raw = store.getSync('sessions', '[]') as string;
      this.sessions = JSON.parse(raw) as PersistSession[];
    } catch (e) {
      this.sessions = [];
    }
  }

  saveCurrentSession(): void {
    if (this.messages.length === 0) {
      return;
    }
    // 无标题（首条用户消息）时不新建会话
    const firstUser = this.messages.find((m: ChatMessage) => m.role === 'user');
    if (!firstUser) {
      return;
    }
    let id = this.currentSessionId;
    if (!id) {
      id = Date.now().toString();
      this.currentSessionId = id;
    }
    const title = firstUser.content.length > 20 ? firstUser.content.substring(0, 20) + '…' : firstUser.content;
    const pmsgs: PersistMessage[] = this.messages.map((m: ChatMessage) => ({
      role: m.role,
      content: m.content,
      time: Date.now()
    } as PersistMessage));
    const session: PersistSession = { id: id, title: title, updatedAt: Date.now(), messages: pmsgs };
    // 替换或追加
    const idx = this.sessions.findIndex((s: PersistSession) => s.id === id);
    if (idx >= 0) {
      this.sessions[idx] = session;
    } else {
      this.sessions.unshift(session);
    }
    // 按更新时间排序
    this.sessions.sort((a: PersistSession, b: PersistSession) => b.updatedAt - a.updatedAt);
    try {
      const store = this.getPrefStore();
      store.putSync('sessions', JSON.stringify(this.sessions));
      store.flush();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'save session failed: %{public}s', (e as Error).message);
    }
  }

  newSession(): void {
    // 先落盘当前会话
    this.saveCurrentSession();
    // 清空消息 + 重置原生多轮上下文
    this.messages = [new ChatMessage('assistant', '你好，我是端语——运行在你设备上的本地对话助手。输入问题开始聊天。')];
    this.currentSessionId = '';
    this.inputText = '';
    if (this.llmSession) {
      mnnllm.reset(this.llmSession);
    }
    this.showSidebar = false;
  }

  switchSession(session: PersistSession): void {
    this.saveCurrentSession();
    this.currentSessionId = session.id;
    this.messages = session.messages.map((m: PersistMessage) => new ChatMessage(m.role as 'user' | 'assistant', m.content));
    // 注意：原生多轮 history 无法从 UI 完全恢复（缺失 think 剥离信息），
    // 简单起见：切会话后重置原生上下文，避免历史错乱
    if (this.llmSession) {
      mnnllm.reset(this.llmSession);
    }
    this.showSidebar = false;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  deleteSession(id: string): void {
    this.sessions = this.sessions.filter((s: PersistSession) => s.id !== id);
    try {
      const store = this.getPrefStore();
      store.putSync('sessions', JSON.stringify(this.sessions));
      store.flush();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'delete session failed: %{public}s', (e as Error).message);
    }
    if (this.currentSessionId === id) {
      this.newSession();
    }
  }

  openProjectPage(): void {
    // TODO: 鸿蒙版仓库尚未创建，先占位跳转用户主页
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://gitee.com/MikeDev'
    };
    this.context.startAbility(want).catch((e: Error) => {
      hilog.warn(0x0000, TAG, 'open browser failed: %{public}s', e.message);
    });
  }

  build() {
    Stack() {
      Column({ space: 0 }) {
        // 顶栏
        Row() {
          // 左侧：标题 + 品牌标识（AI 生成 / 项目主页 竖向堆叠）
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Text('端语')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.textColor())
              Text('本地大模型对话')
                .fontSize(11)
                .fontColor(this.textDimColor())
            }
            .alignItems(HorizontalAlign.Start)
            Column({ space: 6 }) {
              if (this.aiLabelVisible) {
                Text('AI 生成')
                  .fontSize(10)
                  .fontColor(Color.White)
                  .backgroundColor('#666666')
                  .borderRadius(4)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              }
              Text('项目主页')
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor('#0A59F7')
                .borderRadius(4)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .onClick(() => {
                  this.openProjectPage();
                })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Center)

          Blank()

          // 右侧：会话操作按钮（历史 / 参数 / 新对话）
          Row({ space: 8 }) {
            Text('历史')
              .fontSize(12)
              .fontColor(Color.White)
              .backgroundColor('#666666')
              .borderRadius(4)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .onClick(() => {
                this.showSidebar = !this.showSidebar;
              })
            Text('参数')
              .fontSize(12)
              .fontColor(Color.White)
              .backgroundColor('#666666')
              .borderRadius(4)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .onClick(() => {
                this.showSettings = !this.showSettings;
              })
            Text('新对话')
              .fontSize(12)
              .fontColor(Color.White)
              .backgroundColor('#0A59F7')
              .borderRadius(4)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .onClick(() => {
                this.newSession();
              })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(16)

        // 状态区
        Column({ space: 4 }) {
          Text(this.statusText).fontSize(12).fontColor(this.textSubColor())
          Text('模型：' + this.modelDisplayName()).fontSize(11).fontColor(this.textFaintColor())
          // 下载进度条（有下载任务时显示）
          if (this.downloadingModel.length > 0) {
            Column({ space: 3 }) {
              Row() {
                Text('下载 ' + this.downloadFileName).fontSize(10).fontColor(this.textSubColor())
                Blank()
                Text(this.downloadPercent + '%').fontSize(10).fontColor('#0A59F7')
              }
              .width('100%')
              Progress({ value: this.downloadPercent, total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(4)
                .color('#0A59F7')
                .backgroundColor(this.isDark ? '#333333' : '#EEEEEE')
            }
            .width('100%')
            .margin({ top: 2 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 8 })

        // 消息列表
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: ChatMessage) => {
            ListItem() {
              MessageBubble({ msg: msg, isDark: this.isDark })
            }
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          }, (msg: ChatMessage, index: number) => index.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        // 输入区
        Row({ space: 8 }) {
          TextInput({ placeholder: '输入消息…', text: this.inputText })
            .layoutWeight(1)
            .height(44)
            .backgroundColor(this.inputBgColor())
            .fontColor(this.textColor())
            .placeholderColor(this.textDimColor())
            .borderRadius(22)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.inputText = value;
            })
            .onSubmit(() => {
              this.sendMessage();
            })
          Button(this.stopping ? '停止中…' : (this.isGenerating ? '■ 暂停' : '发送'))
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.stopping ? '#999999' : (this.isGenerating ? '#FF6666' : '#0A59F7'))
            .enabled(!this.stopping)
            .onClick(() => {
              if (this.isGenerating) {
                this.stopGenerating();
              } else {
                this.sendMessage();
              }
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.bgColor())
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor())

      // 侧边栏（历史会话列表）
      if (this.showSidebar) {
        Column({ space: 0 }) {
          // 遮罩
          Blank()
            .backgroundColor('#33000000')
            .onClick(() => {
              this.showSidebar = false;
            })
        }
        .width('100%')
        .height('100%')

        // 侧边栏面板
        Column({ space: 0 }) {
          Row() {
            Text('历史会话').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor())
            Blank()
            Text('关闭').fontSize(14).fontColor('#0A59F7')
              .onClick(() => {
                this.showSidebar = false;
              })
          }
          .width('100%')
          .padding(16)

          if (this.sessions.length === 0) {
            Column({ space: 8 }) {
              Text('暂无历史会话').fontSize(14).fontColor(this.textDimColor())
            }
            .width('100%')
            .padding(20)
            .alignItems(HorizontalAlign.Center)
          } else {
            List() {
              ForEach(this.sessions, (s: PersistSession) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Column({ space: 4 }) {
                      Text(s.title).fontSize(14).fontColor(this.textColor()).maxLines(1)
                      Text(this.formatTime(s.updatedAt)).fontSize(11).fontColor(this.textFaintColor())
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Text('删除')
                      .fontSize(12)
                      .fontColor('#FF5555')
                      .onClick(() => {
                        this.deleteSession(s.id);
                      })
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .onClick(() => {
                    this.switchSession(s);
                  })
                }
                .padding({ left: 16, right: 16 })
              }, (s: PersistSession) => s.id)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Off)
          }
        }
        .width('80%')
        .height('100%')
        .backgroundColor(this.panelColor())
        .borderRadius({ topRight: 12, bottomRight: 12 })
        .shadow({ radius: 8, color: '#33000000', offsetX: 2, offsetY: 0 })
      }

      // 参数设置面板
      if (this.showSettings) {
        Column({ space: 0 }) {
          Blank()
            .backgroundColor('#33000000')
            .onClick(() => {
              this.showSettings = false;
            })
        }
        .width('100%')
        .height('100%')

        Column({ space: 16 }) {
          Row() {
            Text('参数设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor())
            Blank()
            Text('关闭').fontSize(14).fontColor('#0A59F7')
              .onClick(() => {
                this.showSettings = false;
              })
          }
          .width('100%')

          Column({ space: 8 }) {
            Row() {
              Text('温度').fontSize(14).fontColor(this.textColor())
              Blank()
              Text(this.temperature.toFixed(2)).fontSize(14).fontColor('#0A59F7')
            }
            .width('100%')
            Slider({ value: this.temperature, min: 0.1, max: 1.5, step: 0.05 })
              .onChange((value: number) => {
                this.temperature = value;
              })
          }
          .width('100%')

          Text('温度越低回答越确定，越高越有创造性（下次对话生效）')
            .fontSize(11)
            .fontColor(this.textDimColor())
            .width('100%')

          // 深色模式开关
          Column({ space: 8 }) {
            Row() {
              Text('深色模式').fontSize(14).fontColor(this.textColor())
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isDark })
                .onChange((isOn: boolean) => {
                  this.isDark = isOn;
                  this.updateWindowBg();
                })
            }
            .width('100%')
          }
          .width('100%')

          // 思考模式开关
          Column({ space: 8 }) {
            Row() {
              Text('思考模式').fontSize(14).fontColor(this.textColor())
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.thinkingEnabled })
                .onChange((isOn: boolean) => {
                  this.thinkingEnabled = isOn;
                  this.toggleThinking();
                })
            }
            .width('100%')
            Text('关闭后模型直接回答，不输出思考过程（仅对支持思考的模型生效）')
              .fontSize(10)
              .fontColor(this.textFaintColor())
              .width('100%')
          }
          .width('100%')

          // API 服务开关
          Column({ space: 8 }) {
            Row() {
              Text('API 服务').fontSize(14).fontColor(this.textColor())
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.apiEnabled })
                .onChange((isOn: boolean) => {
                  this.toggleApi();
                })
            }
            .width('100%')
            Text('状态：' + this.apiStatus).fontSize(11).fontColor(this.textDimColor()).width('100%')
            // 访问令牌输入框（空 = 不鉴权）
            TextInput({ placeholder: '访问令牌（留空不鉴权）', text: this.apiToken })
              .height(36)
              .backgroundColor(this.inputBgColor())
              .fontColor(this.textColor())
              .placeholderColor(this.textDimColor())
              .borderRadius(8)
              .onChange((value: string) => {
                this.apiToken = value;
              })
            Text('局域网设备可通过 http://<本机IP>:8080/v1/chat/completions 调用本地模型')
              .fontSize(10)
              .fontColor(this.textFaintColor())
              .width('100%')
          }
          .width('100%')

          // 模型管理入口
          Column({ space: 8 }) {
            Row() {
              Text('模型管理').fontSize(14).fontColor(this.textColor())
              Blank()
              Text(this.modelDisplayName()).fontSize(12).fontColor('#0A59F7')
              Text('›').fontSize(16).fontColor(this.textDimColor())
            }
            .width('100%')
            .onClick(() => {
              this.refreshDownloadedModels();
              this.showModelManager = true;
              this.showSettings = false;
            })
          }
          .width('100%')

          // 关于与合规入口
          Column({ space: 8 }) {
            Row() {
              Text('关于与合规').fontSize(14).fontColor(this.textColor())
              Blank()
              Text('›').fontSize(16).fontColor(this.textDimColor())
            }
            .width('100%')
            .onClick(() => {
              this.showSettings = false;
              router.pushUrl({ url: 'pages/About' });
            })
          }
          .width('100%')

          Button('应用并继续')
            .width('100%')
            .height(44)
            .onClick(() => {
              this.applySettings();
              this.showSettings = false;
            })
        }
        .width('80%')
        .padding(20)
        .backgroundColor(this.panelColor())
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }

      // 模型管理面板
      if (this.showModelManager) {
        Column({ space: 0 }) {
          Blank()
            .backgroundColor('#33000000')
            .onClick(() => {
              this.showModelManager = false;
            })
        }
        .width('100%')
        .height('100%')

        Column({ space: 12 }) {
          Row() {
            Text('模型管理').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor())
            Blank()
            Text('关闭').fontSize(14).fontColor('#0A59F7')
              .onClick(() => {
                this.showModelManager = false;
              })
          }
          .width('100%')

          List() {
            ForEach(MODEL_LIST, (spec: ModelSpec) => {
              ListItem() {
                Column({ space: 6 }) {
                  Row() {
                    Text(spec.displayName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.textColor())
                    Blank()
                    this.modelActionButton(spec)
                  }
                  .width('100%')
                  Text(spec.desc).fontSize(11).fontColor(this.textDimColor()).width('100%')
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              }
              .padding({ left: 4, right: 4 })
            }, (spec: ModelSpec) => spec.id)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
        .width('85%')
        .padding(20)
        .backgroundColor(this.panelColor())
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor())
  }

  modelDisplayName(): string {
    const spec = MODEL_LIST.find((m: ModelSpec) => m.id === this.currentModelId);
    return spec ? spec.displayName : this.currentModelId;
  }

  // ============ 主题色（深色模式） ============
  // 通过 getter 集中管理颜色，深色模式只需切换 isDark
  bgColor(): string { return this.isDark ? '#1A1A1A' : '#FFFFFF'; }
  panelColor(): string { return this.isDark ? '#1E1E1E' : '#FFFFFF'; }
  textColor(): string { return this.isDark ? '#E0E0E0' : '#222222'; }
  textSubColor(): string { return this.isDark ? '#9E9E9E' : '#888888'; }
  textDimColor(): string { return this.isDark ? '#777777' : '#999999'; }
  textFaintColor(): string { return this.isDark ? '#555555' : '#aaaaaa'; }
  bubbleAiColor(): string { return this.isDark ? '#2A2A2A' : '#F0F0F0'; }
  bubbleThinkColor(): string { return this.isDark ? '#333333' : '#F7F7F7'; }
  thinkTextColor(): string { return this.isDark ? '#8A8A8A' : '#999999'; }
  inputBgColor(): string { return this.isDark ? '#2A2A2A' : '#F5F5F5'; }
  statsTextColor(): string { return this.isDark ? '#666666' : '#bbbbbb'; }

  // 模型操作按钮：使用中 / 切换 / 下载中 / 下载
  @Builder
  modelActionButton(spec: ModelSpec) {
    if (spec.id === this.currentModelId) {
      Text('使用中')
        .fontSize(12)
        .fontColor('#ffffff')
        .backgroundColor('#0A59F7')
        .borderRadius(4)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    } else if (this.downloadingModel === spec.id) {
      Text(this.downloadPercent + '%')
        .fontSize(12)
        .fontColor('#0A59F7')
        .backgroundColor('#EEF3FF')
        .borderRadius(4)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    } else if (this.downloadedModels.includes(spec.id)) {
      Row({ space: 8 }) {
        Text('删除')
          .fontSize(12)
          .fontColor('#FF5555')
          .onClick(() => {
            this.deleteModel(spec.id);
          })
        Text('切换')
          .fontSize(12)
          .fontColor('#ffffff')
          .backgroundColor('#0A59F7')
          .borderRadius(4)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => {
            this.switchModel(spec.id);
          })
      }
    } else {
      Text('下载')
        .fontSize(12)
        .fontColor('#0A59F7')
        .borderColor('#0A59F7')
        .borderWidth(1)
        .borderRadius(4)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .onClick(() => {
          this.switchModel(spec.id);   // 未下载时切过去会自动触发下载
        })
    }
  }

  applySettings(): void {
    if (this.llmSession) {
      const cfg = '{"temperature":' + this.temperature.toFixed(2) + '}';
      mnnllm.setConfig(this.llmSession, cfg);
      hilog.info(0x0000, TAG, 'apply settings: %{public}s', cfg);
    }
  }

  // 思考模式开关：Qwen3 系列生效（Qwen2.5 无思考链则无效果）
  toggleThinking(): void {
    if (this.llmSession) {
      mnnllm.setThinking(this.llmSession, this.thinkingEnabled);
      hilog.info(0x0000, TAG, 'thinking: %{public}s', this.thinkingEnabled ? 'on' : 'off');
    }
  }

  // 更新窗口背景色（状态栏/导航栏避让区域跟随深色模式，消除上下白边）
  updateWindowBg(): void {
    try {
      window.getLastWindow(this.context).then((win: window.Window) => {
        win.setWindowBackgroundColor(this.isDark ? '#1A1A1A' : '#FFFFFF');
      }).catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'set window bg failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'get window failed: %{public}s', (e as Error).message);
    }
  }

  // ============ API 服务 ============
  toggleApi(): void {
    if (this.apiEnabled) {
      this.stopApi();
    } else {
      this.startApi();
    }
  }

  async startApi(): Promise<void> {
    if (!this.llmSession) {
      this.apiStatus = '引擎未就绪';
      return;
    }
    // 注入推理回调（用 submitSync 拿到完整回复）
    this.apiServer.setInference((prompt: string): Promise<string> => {
      return mnnllm.submitSync(this.llmSession!, prompt);
    });
    // 注入流式推理回调（submit + poll 轮询，逐 chunk 回调）
    this.apiServer.setStreamInference((prompt: string, onChunk: (text: string) => void): Promise<void> => {
      return new Promise<void>((resolve, reject) => {
        mnnllm.submit(this.llmSession!, prompt);
        let timer: number = 0;
        const doPoll = (): void => {
          try {
            const r = mnnllm.poll(this.llmSession!);
            if (r.chunk.length > 0) {
              onChunk(r.chunk);
            }
            if (r.error.length > 0) {
              clearInterval(timer);
              reject(new Error(r.error));
            }
            if (r.done) {
              clearInterval(timer);
              resolve();
            }
          } catch (e) {
            clearInterval(timer);
            reject(e as Error);
          }
        };
        doPoll();
        timer = setInterval(doPoll, 30);
      });
    });
    // 设置访问令牌（空 = 不鉴权）
    this.apiServer.setAuthToken(this.apiToken.trim());
    const ok = await this.apiServer.start();
    if (ok) {
      this.apiEnabled = true;
      this.apiStatus = '运行中 :8080';
    } else {
      this.apiStatus = '启动失败';
    }
  }

  async stopApi(): Promise<void> {
    await this.apiServer.stop();
    this.apiEnabled = false;
    this.apiStatus = '未启动';
  }

  formatTime(ts: number): string {
    const d = new Date(ts);
    const mm = (d.getMonth() + 1).toString().padStart(2, '0');
    const dd = d.getDate().toString().padStart(2, '0');
    const hh = d.getHours().toString().padStart(2, '0');
    const mi = d.getMinutes().toString().padStart(2, '0');
    return mm + '-' + dd + ' ' + hh + ':' + mi;
  }
}
