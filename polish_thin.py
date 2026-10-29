# -*- coding: utf-8 -*-
"""瘦数据润色：8 条核心 JS 概念定义归一（目标 70-90 字）"""
import json
import sys
import shutil

PATH = 'assets/data/concepts.json'

NEW = {
    '变量提升': 'var 声明的变量和函数声明会被提升到作用域顶部：var 变量提升后为 undefined，函数声明整体可用。let、const 提升后处于暂时性死区，声明前访问报错。',
    '闭包': '闭包是函数与其词法作用域的组合。内层函数引用外层变量，即使外层函数已执行完毕，变量仍被保留不释放。常用于封装私有变量和函数工厂，滥用会导致内存泄漏。',
    '原型链': '访问对象属性时若自身没有，引擎会沿 __proto__ 指向的原型对象逐级向上查找，直到 null，这条路径就是原型链。它是 JS 实现继承与属性共享的基础。',
    '事件冒泡': '事件从目标元素开始逐级向上传播到 document，这个过程叫冒泡。addEventListener 默认在冒泡阶段触发，所以子元素的事件也会惊动父元素的监听器。',
    '事件委托': '把多个子元素的监听器统一挂到共同父元素上，靠冒泡在回调里用 event.target 判断真正触发的是谁。只绑一次、动态新增的子元素自动生效，内存更省。',
    'Promise': 'Promise 是异步操作的状态容器，pending、fulfilled、rejected 三态不可逆。then 接成功、catch 捕失败、finally 收尾，把回调地狱改链。',
    'async/await': 'async 修饰的函数返回 Promise，await 等 Promise 结果，让异步代码写出同步顺序。await 只在 async 内有效，错误用 try/catch 捕获。',
    'DOM': 'DOM 是浏览器解析 HTML 后生成的节点树，JS 靠它读写页面。常用 querySelector 查、createElement 建、classList 改样式，操作触发重排。',
}


def main():
    dry = '--dry' in sys.argv
    with open(PATH, encoding='utf-8') as f:
        data = json.load(f)

    hit = 0
    for item in data:
        term = item.get('term')
        if term in NEW:
            old_len = len(item['definition'])
            new_len = len(NEW[term])
            print('%-12s %3d -> %3d' % (term, old_len, new_len))
            if not dry:
                item['definition'] = NEW[term]
            hit += 1

    print('命中 %d/%d' % (hit, len(NEW)))
    miss = [t for t in NEW if t not in [x.get('term') for x in data]]
    print('未命中:', miss if miss else '无')

    if hit != len(NEW):
        print('!! 命中数不符，终止')
        raise SystemExit(1)

    out_of_range = [t for t in NEW if not (70 <= len(NEW[t]) <= 90)]
    print('越界(非70-90):', out_of_range if out_of_range else '无')

    if dry:
        print('[DRY] 未写入')
        return

    if out_of_range:
        print('!! 存在越界项，拒绝写入')
        raise SystemExit(1)

    shutil.copy(PATH, PATH + '.bak_polish')
    with open(PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    with open(PATH, encoding='utf-8') as f:
        d2 = json.load(f)
    lens = [len(x['definition']) for x in d2]
    print('写入后条数:', len(d2))
    print('def_len min/max/avg: %d/%d/%.1f' % (min(lens), max(lens), sum(lens) / len(lens)))
    short = [x['term'] for x in d2 if len(x['definition']) < 30]
    print('仍<30字的:', short if short else '无')


if __name__ == '__main__':
    main()