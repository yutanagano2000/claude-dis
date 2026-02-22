#!/usr/bin/env python3
"""DIS: TF-IDF類似度スコアリング。新規エラーと既存solutionsのマッチング。"""
import math
import re
import sqlite3
import os
from collections import Counter

DB = os.path.expanduser("~/.claude/intelligence/dev.db")


def tokenize(text: str) -> list[str]:
    """テキストをトークンに分割。"""
    text = text.lower()
    text = re.sub(r"[^a-z0-9_]", " ", text)
    return [t for t in text.split() if len(t) > 2]


def compute_tf(tokens: list[str]) -> dict[str, float]:
    """Term Frequency計算。"""
    counts = Counter(tokens)
    total = len(tokens) or 1
    return {t: c / total for t, c in counts.items()}


def compute_idf(documents: list[list[str]]) -> dict[str, float]:
    """Inverse Document Frequency計算。"""
    n = len(documents) or 1
    df = Counter()
    for doc in documents:
        for t in set(doc):
            df[t] += 1
    return {t: math.log(n / (1 + c)) for t, c in df.items()}


def cosine_similarity(v1: dict[str, float], v2: dict[str, float]) -> float:
    """コサイン類似度。"""
    keys = set(v1) & set(v2)
    if not keys:
        return 0.0
    dot = sum(v1[k] * v2[k] for k in keys)
    mag1 = math.sqrt(sum(v ** 2 for v in v1.values()))
    mag2 = math.sqrt(sum(v ** 2 for v in v2.values()))
    if mag1 == 0 or mag2 == 0:
        return 0.0
    return dot / (mag1 * mag2)


def find_similar(error_text: str, threshold: float = 0.5, limit: int = 5) -> list[dict]:
    """エラーテキストに類似する既存solutionsを検索。"""
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    cur.execute("SELECT id, error_pattern, solution, score FROM solutions ORDER BY score DESC LIMIT 200")
    rows = cur.fetchall()
    conn.close()

    if not rows:
        return []

    query_tokens = tokenize(error_text)
    if not query_tokens:
        return []

    doc_tokens = [tokenize(row[1]) for row in rows]
    all_docs = [query_tokens] + doc_tokens
    idf = compute_idf(all_docs)

    query_tfidf = {t: tf * idf.get(t, 0) for t, tf in compute_tf(query_tokens).items()}

    results = []
    for i, row in enumerate(rows):
        doc_tf = compute_tf(doc_tokens[i])
        doc_tfidf = {t: tf * idf.get(t, 0) for t, tf in doc_tf.items()}
        sim = cosine_similarity(query_tfidf, doc_tfidf)
        if sim >= threshold:
            results.append({
                "id": row[0],
                "pattern": row[1],
                "solution": row[2],
                "score": row[3],
                "similarity": round(sim, 3),
            })

    results.sort(key=lambda x: x["similarity"], reverse=True)
    return results[:limit]


def merge_similar_solutions(threshold: float = 0.7):
    """類似度が高いsolution同士をマージ。"""
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    cur.execute("SELECT id, error_pattern, success_count, score FROM solutions ORDER BY score DESC")
    rows = cur.fetchall()

    if len(rows) < 2:
        conn.close()
        return

    doc_tokens = [tokenize(row[1]) for row in rows]
    idf = compute_idf(doc_tokens)

    merged_ids = set()
    merge_count = 0

    for i in range(len(rows)):
        if rows[i][0] in merged_ids:
            continue
        tf_i = compute_tf(doc_tokens[i])
        tfidf_i = {t: tf * idf.get(t, 0) for t, tf in tf_i.items()}

        for j in range(i + 1, len(rows)):
            if rows[j][0] in merged_ids:
                continue
            tf_j = compute_tf(doc_tokens[j])
            tfidf_j = {t: tf * idf.get(t, 0) for t, tf in tf_j.items()}

            sim = cosine_similarity(tfidf_i, tfidf_j)
            if sim >= threshold:
                # jをiにマージ（スコアが高い方に統合）
                cur.execute(
                    "UPDATE solutions SET success_count = success_count + ?, score = score + ? WHERE id = ?",
                    (rows[j][2], rows[j][3] * 0.5, rows[i][0]),
                )
                cur.execute("DELETE FROM solutions WHERE id = ?", (rows[j][0],))
                merged_ids.add(rows[j][0])
                merge_count += 1

    conn.commit()
    conn.close()
    print(f"Merged {merge_count} similar solutions")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--merge":
        merge_similar_solutions()
    elif len(sys.argv) > 1:
        results = find_similar(" ".join(sys.argv[1:]))
        for r in results:
            print(f"[sim={r['similarity']:.2f} score={r['score']:.1f}] {r['pattern'][:80]}")
            print(f"  → {r['solution'][:120]}")
            print()
        if not results:
            print("No similar solutions found.")
    else:
        print("Usage: similarity.py <error_text>  |  similarity.py --merge")
