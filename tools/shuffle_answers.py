#!/usr/bin/env python3
# Deterministic MCQ option shuffler.
# Reads the pristine baseline backup, writes questions.json.
# Idempotent: output depends only on the backup + per-question seed.
import json, hashlib, random, sys
from collections import Counter

SRC = 'assets/data/questions.json.bak_w14pre'
DST = 'assets/data/questions.json'

def seeded_rng(qid):
    h = hashlib.sha256(('studytracker:' + qid).encode('utf-8')).hexdigest()[:16]
    return random.Random(int(h, 16))

def main():
    d = json.load(open(SRC, encoding='utf-8'))
    before = Counter(q['answer'] for q in d['mcq'])
    for q in d['mcq']:
        opts = list(q['options'])
        assert len(opts) == 4, q['id']
        correct = opts[q['answer']]
        rng = seeded_rng(q['id'])
        rng.shuffle(opts)
        q['options'] = opts
        q['answer'] = opts.index(correct)
        assert opts[q['answer']] == correct
    assert len(d['mcq']) == 276, len(d['mcq'])
    json.dump(d, open(DST, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    after = Counter(q['answer'] for q in d['mcq'])
    print('before:', dict(sorted(before.items())))
    print('after :', dict(sorted(after.items())))
    print('md5   :', hashlib.md5(open(DST, 'rb').read()).hexdigest())

if __name__ == '__main__':
    main()
