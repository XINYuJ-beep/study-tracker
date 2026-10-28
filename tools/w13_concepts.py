# -*- coding: utf-8 -*-
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONCEPTS = os.path.join(ROOT, 'assets', 'data', 'concepts.json')
WEEK = 13
LO, HI = 45, 95
HARD_LO, HARD_HI = 40, 100

NEW = [
    ("类型注解", "写在变量后面用冒号标出类型，告诉编译器这个东西是什么，写错了当场报错，不用等运行时才发现。"),
    ("类型推断", "你省略类型标注时，编译器自己按初始值或上下文算出变量该是什么类型，多数场合够用，所以新手不必到处写冒号。"),
    ("静态类型检查", "在编译阶段就把类型错误挑出来，不用跑起来才崩，重构时改一处类型编译器帮你把牵连的地方全找出来。"),
    ("any 等于关掉检查", "标成 any 就放弃了这个值的所有类型保护，能不用就不用，用多了等于白上 TypeScript。"),
    ("unknown 比 any 安全", "unknown 表示还不知道是什么，用之前必须收窄，any 是随便用，拿不准时选 unknown 让编译器盯着你。"),
    ("void 与 undefined", "函数返回 void 表示不关心返回值，调用处别拿它的结果用；undefined 是一个真实存在的值，两者不是一回事。"),
    ("never 表示不可能", "用在永远不返回的函数或永远进不去的分支上，比如抛异常、死循环，它也用来做穷尽性检查的兜底。"),
    ("interface 描述对象", "用 interface 给对象定形状，写清有哪些字段、各是什么类型，对象写错字段名或类型时编译直接报错。"),
    ("可选属性与只读", "字段名后加问号表示可以不传，加 readonly 表示初始化后不能再改，把契约写进类型而不是靠注释提醒。"),
    ("索引签名", "对象字段名不固定时用索引签名[键: string]: 类型，告诉编译器任意字符串键都对应同一类值。"),
    ("interface 合并", "同名 interface 会声明合并，多的字段拼一起；extends 则继承过来，适合给第三方类型做扩展。"),
    ("type 与 interface 取舍", "对象结构两边都能写，需要合并或 extends 用 interface，需要联合、交叉、映射这类运算就用 type。"),
    ("函数参数注解", "参数逐个标类型，返回值也标上，标了返回值编译器就会回头检查每条 return 是否都对得上。"),
    ("可选参数与默认值", "参数后加问号表示可选，且必须排在必选参数之后；给默认值时类型由默认值推断，调用方可传可不传。"),
    ("函数重载", "同一个函数名按不同参数组合写多份签名，最后一份实现兜底，调用时按签名匹配出对应返回值类型。"),
    ("泛型是类型的参数", "把类型当成参数传进去，一份代码适配多种类型还保留类型信息，比 any 强在返回类型不会丢。"),
    ("泛型约束", "用 extends 限定泛型能是什么，比如要求有 length 字段，这样函数体里就能安全访问这个字段。"),
    ("泛型默认值", "给类型参数设一个不传就用的默认值，比如不写 T 时默认按 unknown 处理，让调用方少写一截，写法是 T = unknown。"),
    ("联合类型", "用竖线把多个类型连起来表示可以是其中之一，用之前必须先收窄，否则只能访问几种类型共同的成员。"),
    ("交叉类型", "用 & 把多个类型合并成一个，值必须同时满足全部结构才算合法，常用于给对象叠加额外能力或拼装接口。"),
    ("字面量类型", "直接拿具体的值当类型，比如只允许 success 或 fail，比宽泛的 string 更精确，能挡住拼错。"),
    ("as const", "让对象里每个字段都变成只读的字面量类型，编译器就不会把字符串宽泛成 string，做常量表和配置字典时特别顺手。"),
    ("类型断言", "用 as 告诉编译器我知道这是什么，它不做运行时校验，断言错了编译不报错只会在运行时炸掉。"),
    ("非空断言", "变量后加感叹号表示我保证它不是 null 或 undefined，纯粹是关掉检查，能靠收窄解决就别用它。"),
    ("类型守卫函数", "写一个返回类型谓词的函数，用 is 标出收窄后的类型，调用后编译器就认这个结果，适合复杂判断。"),
    ("可辨识联合", "每种情况带一个共同的字段值当标记，switch 这个字段就能自动收窄，安全写多分支就靠它。"),
    ("穷尽性检查", "switch 所有分支写完后在 default 里把值赋给 never，将来新增一种情况忘处理编译器立刻报错。"),
    ("typeof 在类型位置", "在类型位置上写 typeof 变量能取出这个变量的类型，省得为了写类型把同样的结构再声明一遍。"),
    ("keyof 取键集合", "keyof 对象类型得到所有键组成的联合类型，配合索引访问就能写出跟着对象自动变的工具类型。"),
    ("索引访问类型", "用 T['某个键'] 的写法从类型里取字段类型，像查对象取值一样查类型，还能配合 keyof 遍历所有键批量取。"),
    ("映射类型", "在类型上遍历键做批量改写，比如一次把全部字段变可选或只读，内置的工具类型底层都是它实现的。"),
    ("条件类型", "写成 A extends B ? X : Y 这种三元式，类型层面按条件分支决定结果，联合类型碰到它会逐项分发，是高级工具类型的核心。"),
    ("infer 提取类型", "在条件类型里用 infer 把某段类型占住再取出来，取函数返回值类型、数组元素类型都靠它。"),
    ("Partial 与 Required", "Partial 把所有字段变可选，Required 变必填，做更新参数和补全默认值这两件事最常用。"),
    ("Pick 与 Omit", "Pick 挑出几个字段组成新类型，Omit 去掉几个字段，从大类型裁出小类型不用再重写一遍。"),
    ("Record 造字典", "Record 用键集合和值类型快速造出字典类型，比索引签名更明确，键的取值范围能直接写死。"),
    ("Exclude 与 Extract", "Exclude 从联合里去掉一部分，Extract 只留一部分，做类型筛选的时候直接套用。"),
    ("NonNullable 与 ReturnType", "NonNullable 去掉 null 和 undefined，ReturnType 取函数返回值类型，省得手动抄一遍。"),
    ("tsc 与 tsconfig", "tsc 是编译器，tsconfig.json 是它的说明书，告诉它编译哪些文件、编成什么目标、开哪些检查。"),
    ("strict 系列开关", "strict 一次打开所有严格检查，新项目别关，旧项目逐个开 strictNullChecks 这类单项慢慢收紧。"),
    ("noImplicitAny", "严格模式下禁止不写类型的参数隐式变成 any，一开这个选项就逼着你把函数签名补齐，正好是新手打类型基本功的地方。"),
    ("strictNullChecks", "让 null 和 undefined 变成独立类型，不再能随便塞给别的类型，副作用最明显的一项检查。"),
    ("target 与 module", "target 决定编译产出什么语法版本，module 决定用什么模块格式，两个是不同维度别混。"),
    ("outDir 与 rootDir", "rootDir 定源码根目录，outDir 定产出目录，两处对齐才能让编译结果保持原目录结构。"),
    ("类型声明文件", "后缀 d.ts 的文件只放类型不放代码，专门给没有类型的库补形状，编译时读取但不影响运行。"),
    ("declare 关键字", "declare 用来声明一个运行时已经存在的值，只给编译器看，不会生成任何实际执行的代码。"),
    ("给 JS 库补类型", "库没自带类型时先查社区类型包，没有再自己写 d.ts 声明用到的部分，够用就行不必写完整。"),
    ("allowJs 与渐进迁移", "开 allowJs 让 JS 和 TS 混着编译，老项目从单个文件改起，不用一次性全部重写。"),
    ("把 JS 改成 TS 的顺序", "先把 tsconfig 的 allowJs 打开，从入口文件开始一个一个改成 .ts，边改边修类型报错，最后全部改完再开严格模式。"),
    ("第三方库类型来源", "类型来自库自带的 types 字段、社区维护的类型包、或自己写的声明文件，排查按这个顺序来。"),
    ("类型检查与运行时边界", "编译器只在写代码时挑错，类型在编译后全部被抹掉，所以接口返回的数据在运行期间不受任何校验，该判空还是得判。"),
    ("W13 知识地图", "本周主线是给 JS 加类型：注解与推断打底，接口和泛型建模，联合收窄做分支，工具类型做加工。"),
]


def main():
    apply = '--apply' in sys.argv
    data = json.load(open(CONCEPTS, encoding='utf-8'))
    before = len(data)
    exist13 = len([x for x in data if x.get('week') == WEEK])
    existing = set(x.get('term', '') for x in data)

    lens = [len(d) for _, d in NEW]
    print('mode            =', 'APPLY' if apply else 'DRY')
    print('before total    =', before)
    print('week13 existing =', exist13)
    print('new count       =', len(NEW))
    print('len min/max/avg =', min(lens), max(lens), round(sum(lens) / len(lens), 1))

    bad = []
    dup = []
    for t, d in NEW:
        if not (HARD_LO <= len(d) <= HARD_HI):
            bad.append((t, len(d)))
        if t in existing:
            dup.append(t)
    print('out_of_range    =', bad)
    print('duplicate       =', dup)
    print('soft_out_of_band=', [(t, len(d)) for t, d in NEW if not (LO <= len(d) <= HI)])

    if bad or dup:
        print('ABORT: fix problems first')
        sys.exit(1)

    if apply:
        for t, d in NEW:
            data.append({'term': t, 'definition': d, 'week': WEEK})
        with open(CONCEPTS, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write('\n')
        print('APPLIED -> total', len(data), '| week13', len([x for x in data if x.get('week') == WEEK]))
    else:
        print('DRY OK -> would become total', before + len(NEW), '| week13', exist13 + len(NEW))


if __name__ == '__main__':
    main()
