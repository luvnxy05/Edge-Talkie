#!/usr/bin/env python3
"""批量验证 MNN 组织所有可下载模型（模拟 App 下载链路：resolve 探测 → LFS 判定 → Range 分段）

App 端逻辑（Index.ets downloadFile）：
  1. 请求 resolve 端点（不跟随重定向）
  2. 返回 200  → 普通文件，响应体即内容（直接下载）
  3. 抛异常/302 → LFS 大文件，对 resolve 端点发 Range，跟随 302 到 CDN 应返回 206
本脚本用 curl 复现同一链路，逐文件校验。
"""
import json
import re
import subprocess
import sys
import concurrent.futures

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
BASE = "https://modelscope.cn"
# 与 App 端 fetchRemoteModels 的 EXCLUDE 正则保持一致
EXCLUDE = re.compile(r'(VL|OCR|Audio|GUI|Extract|Math|RAG|Tool|Transcript|PII|JP|Exp|Dflash|Draft|Embedding|Guard|Eagle|Omni|Reranker|vits|piper|Avatar|Talker|bge|Prover|reader-lm|CPM-V|MT-)', re.I)


def curl(args, timeout=40):
    try:
        r = subprocess.run(['curl', '-s', '-m', str(timeout)] + args,
                           capture_output=True, text=True)
        return r.stdout
    except Exception:
        return ''


def http_code(url, follow=False, rng=None, timeout=40):
    args = ['-o', '/dev/null', '-w', '%{http_code}']
    if follow:
        args.append('-L')
    if rng:
        args += ['-r', rng]
    args.append(url)
    return curl(args, timeout).strip()


def fetch_models():
    all_models = []
    for page in range(1, 6):
        body = json.dumps({
            "PageSize": 100, "PageNumber": page, "SortBy": "GmtModified", "Name": "",
            "IncludePrePublish": True,
            "Criterion": [{"category": "organizations", "predicate": "contains", "values": ["MNN"]}]
        })
        out = curl(['-X', 'PUT', f'{BASE}/api/v1/dolphin/models',
                    '-H', 'Content-Type: application/json', '-d', body])
        models = json.loads(out)['Data']['Model']['Models']
        if not models:
            break
        all_models.extend(models)
        if len(models) < 100:
            break
    return all_models


def fetch_files(model_id):
    out = curl([f'{BASE}/api/v1/models/MNN/{model_id}/repo/files?Recursive=true&Revision=master'])
    d = json.loads(out)
    return [f for f in d['Data']['Files']
            if f['Path'] != 'README.md' and '.gitattributes' not in f['Path']]


def verify_model(m):
    name = m['Name']
    try:
        files = fetch_files(name)
        if not files:
            return (name, 'FAIL', 'no files')
        bad = []
        for f in files:
            p = f['Path']
            url = f"{BASE}/models/MNN/{name}/resolve/master/{p}"
            code = http_code(url, follow=False)
            if code == '302':
                # LFS 大文件：跟随重定向 + Range 应为 206（App 端走这条）
                code2 = http_code(url, follow=True, rng='0-99')
                if code2 not in ('206', '200'):
                    bad.append(f"{p}=range:{code2}")
            elif code == '200':
                pass  # 普通文件，App 端直接下载
            else:
                bad.append(f"{p}=probe:{code}")
        if bad:
            return (name, 'FAIL', '; '.join(bad))
        return (name, 'OK', f"{len(files)} files")
    except Exception as e:
        return (name, 'FAIL', str(e)[:120])


def main():
    models = fetch_models()
    filtered = [m for m in models
                if m['Name'].endswith('-MNN') and not EXCLUDE.search(m['Name'])]
    print(f"魔搭 MNN 组织共 {len(models)} 个模型，过滤后 {len(filtered)} 个待验证", flush=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        for r in ex.map(verify_model, filtered):
            results.append(r)
            print(f"[{r[1]}] {r[0]} - {r[2]}", flush=True)
    ok = sum(1 for r in results if r[1] == 'OK')
    print(f"\n=== 汇总: {ok}/{len(results)} 通过 ===", flush=True)
    for r in results:
        if r[1] != 'OK':
            print(f"FAIL: {r[0]} - {r[2]}", flush=True)


if __name__ == '__main__':
    main()
