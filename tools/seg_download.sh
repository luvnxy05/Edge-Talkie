#!/bin/bash
# 分段下载 ModelScope 大文件（直接连 CDN，支持 Range）
# 用法: ./seg_download.sh <model> <file>
set -u
MODEL="$1"
FILE="$2"
DEST_DIR="/Users/mike/Projects/mnn-harmony-chat/models/$MODEL"
cd "$DEST_DIR"

# 1. 拿到 CDN 直链（302 重定向目标）
REDIRECT=$(curl -s -m 20 -D - -o /dev/null -H "User-Agent: Mozilla/5.0" \
  "https://modelscope.cn/models/MNN/$MODEL/resolve/master/$FILE" 2>/dev/null \
  | grep -i "^location:" | sed 's/[Ll]ocation: //' | tr -d '\r')
if [ -z "$REDIRECT" ]; then
  echo "无法获取 CDN 直链"
  exit 1
fi

# 2. 拿文件总大小
TOTAL=$(curl -s -m 20 -D - -o /dev/null -H "Range: bytes=0-0" -H "User-Agent: Mozilla/5.0" "$REDIRECT" 2>/dev/null \
  | grep -i "content-range" | sed 's/.*\///' | tr -d '\r')
if [ -z "$TOTAL" ]; then
  echo "无法获取文件大小"
  exit 1
fi
echo "文件总大小: $TOTAL 字节"

# 3. 分段下载（每段 64MB，16 段覆盖 1GB）
SEG=67108864  # 64MB
PART_DIR="$DEST_DIR/.parts_$FILE"
mkdir -p "$PART_DIR"

offset=0
idx=0
while [ "$offset" -lt "$TOTAL" ]; do
  end=$((offset + SEG - 1))
  [ "$end" -ge "$TOTAL" ] && end=$((TOTAL - 1))
  part="$PART_DIR/part_$(printf '%03d' $idx)"
  if [ -f "$part" ] && [ "$(stat -f%z "$part" 2>/dev/null || echo 0)" -eq $((end - offset + 1)) ]; then
    echo "段 $idx 已存在，跳过"
  else
    echo "下载段 $idx: bytes=$offset-$end"
    curl -s -m 300 --retry 5 --retry-delay 2 -H "Range: bytes=$offset-$end" \
      -H "User-Agent: Mozilla/5.0" -o "$part" "$REDIRECT" 2>&1
    # 校验段大小
    got=$(stat -f%z "$part" 2>/dev/null || echo 0)
    want=$((end - offset + 1))
    if [ "$got" -ne "$want" ]; then
      echo "  ⚠️ 段 $idx 大小不对：$got != $want，重试"
      rm -f "$part"
      continue
    fi
  fi
  offset=$((end + 1))
  idx=$((idx + 1))
done

# 4. 合并
echo "合并 $idx 段..."
: > "$FILE"
for i in $(seq 0 $((idx - 1))); do
  cat "$PART_DIR/part_$(printf '%03d' $i)" >> "$FILE"
done

# 5. 校验
SIZE=$(stat -f%z "$FILE" 2>/dev/null || echo 0)
echo "合并完成: $SIZE 字节 (期望 $TOTAL)"
if [ "$SIZE" -eq "$TOTAL" ]; then
  echo "✅ 下载完整"
  rm -rf "$PART_DIR"
else
  echo "❌ 大小不符，保留分段目录供重试"
fi
