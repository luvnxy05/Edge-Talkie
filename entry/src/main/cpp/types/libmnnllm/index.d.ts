export interface PollResult {
  chunk: string;   // 新生成内容（取走后清空）
  done: boolean;   // 推理是否完成
  error: string;   // 错误信息（空串 = 无错误）
  promptTokens: number;
  outputTokens: number;
  tokPerSec: number;
}

export interface LlmSession {
  init(modelDir: string): Object;
  submit(session: Object, prompt: string): void;
  submitSync(session: Object, prompt: string): Promise<string>;
  poll(session: Object): PollResult;
  setConfig(session: Object, jsonConfig: string): void;
  stop(session: Object): void;
  setThinking(session: Object, enabled: boolean): void;
  reset(session: Object): void;
  release(session: Object): void;
}

declare const mnnllm: LlmSession;
export default mnnllm;
