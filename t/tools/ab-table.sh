#!/usr/bin/env bash
# ab-table.sh — ApacheBench の出力ファイルを横並びの比較表にする
#
# 使い方:
#   ab -n 2000 -c 100 -l https://example.com/ > before_c100.txt
#   ab -n 2000 -c 100 -l https://example.com/ > after_c100.txt
#   ./ab-table.sh before_c100.txt after_c100.txt
#
# オプション:
#   --csv   表の代わりに CSV で出力する（スプレッドシートに貼る用）

csv=0
if [ "$1" = "--csv" ]; then csv=1; shift; fi

if [ $# -eq 0 ]; then
  echo "使い方: $0 [--csv] 結果1.txt [結果2.txt ...]" >&2
  exit 1
fi

for f in "$@"; do
  awk -v name="$(basename "$f" .txt)" '
    /^Concurrency Level:/        { c = $3 }
    /^Complete requests:/        { n = $3 }
    /^Failed requests:/          { fail = $3 }
    /^Keep-Alive requests:/      { ka = $3 }
    /^Requests per second:/      { rps = $4 }
    /^Time per request:.*\(mean\)$/ { tpr = $4 }
    /^Connect:/                  { conn = $3 }
    /^Waiting:/                  { wait = $3 }
    /^ +50%/                     { p50 = $2 }
    /^ +95%/                     { p95 = $2 }
    /^ +99%/                     { p99 = $2 }
    /^ +100%/                    { pmax = $2 }
    END {
      printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        name, c, n, (ka == "" ? "なし" : "あり"), fail, rps, tpr,
        conn, wait, p50, p95, p99, pmax
    }' "$f"
done | {
  header="名前,並列数,件数,-k,失敗,req/s,平均応答(ms),Connect平均,TTFB平均,50%,95%,99%,最大"
  if [ $csv -eq 1 ] || ! command -v column >/dev/null; then
    echo "$header"; cat
  else
    { echo "$header"; cat; } | column -t -s,
  fi
}
