---
title: "手写vue3-01实现effect和reactive"
date: 2022-03-08T22:27:32+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

## mini-vue初始化
本系列将会实现一个mini 😊的vue3框架，但是在开始写代码之前需要做一些准备工作，安装相关依赖
1. 安装`typescript`，因为我们要用ts来实现，虽然只是轻量级ts体验，然后才能初始化`tsc --init`，生成tsconfig.json
2. 安装`jest`，做测试用
3. 安装jest配套使用的`babel`, 详见jest官网
4. 创建`babel.config.js`
```javascript
module.exports = {
  presets: [
    ["@babel/preset-env", { targets: { node: "current" } }],
    "@babel/preset-typescript",
  ],
};
```
4. 修改`tsconfig.json`，暂时先改这几个:
```javascript
"target": "es2016", 
"module": "commonjs", 
"types": ["jest"],
```

后面还会改很多……

5. 缺啥依赖安装啥依赖 

### 目录结构
1. 根目录下创建`src`目录，创建`reactivity`子目录，接着在`reactivity目录下`创建`test`子目录
2. 在test目录下创建`index.spec.ts`，写点东西测试一下`jest好用不`

## vue3基础概述
vue3有三大核心： reactivity 响应式模块、runtime 运行时模块（包括element初始化和更新）、compiler 编译模块。
我们先从reactivity模块开始进行，也就是为什么我们需要创建一个`reactivity`目录。
### 实现`reactive`
`reactive`是响应式模块的基础的基础，也是有别于`vue2`的本质所在，我们实现的所有过程都是测试先行，先看看我们正常是怎么使用的，再去一步一步的实现它。
1. `reactivity目录`创建`reactive.ts`，`test目录`创建`reactive.spec.ts`，测试代码如下：

```javascript
// reactive.spec.ts
import { reactive } from "../reactive"

describe("reactive", () => {
  it("happy path", () => {
    const origin = {
      'foo': 1,
    }

    const observed = reactive(origin)
    expect(observed).not.toBe(origin)
    expect(observed.foo).toBe(1)
  })
})
```
根据这个测试代码的`happy path`，也就是所测试模块的核心流程，我们期望`reactive`函数，可以：
- 使一个普通对象变成响应式的，并且和原来不相等
- 能够正常访问原对象的属性值

2. 代理对象，使用`proxy`来实现，最终会返回一个经过我们代理处理后的新的对象，很明显这两个不相等了就，一个基础版的`proxy`写法如下。

```javascript
// reactive.ts
function reactive(raw) {
  return new Proxy(raw, {
    get(target, key) {
      // 当我们获取值的时候触发这里getter处理器，通常用来收集依赖
      track(target, key) // TODO 在effect中实现
      // proxy为什么要配合使用Reflect详见后面的分析
      const value = Reflect.get(target, key)
      return value
    },
    set(target, key, value) {
      // 当我们设置时触发这里的setter处理器，触发上面收集到的依赖
      trigger(target, key) // TODO 在effect中实现
      const result = Reflect.set(target, key, value)

      return result
    },
  })
}

export {
  reactive,
}
```

以上是最基础的代理实现，但是我们还需要收集和触发依赖的逻辑，这就需要用到比较重要的一个概念`effect`，它是一个强大的副作用函数，可以实现依赖收集与触发等等其他复杂的操作。

### 实现`effect`
在`effect`中我们处理所有与依赖有关的操作，相当于是解耦了，响应的代理对象和依赖的操作，也是比较核心的一个模块。
首先，我们要实现两个核心函数`收集track`和`触发trigger`，
其次，我们要明白effect干了什么
照旧，我们先看一下测试用例咋使用：

```javascript
describe("effect", () => {
  it('Happy path', () => {
    const origin = reactive({
      'age': 10
    })

    let nextAge
    effect(() => {
      nextAge = origin.age + 1
    })

    expect(nextAge).toBe(11)

    origin.age = origin.age + 1
    expect(nextAge).toBe(12)
  });
})
```

可以知道：
1. effect中的回调会触发收集依赖，并会被立刻执行一次
2. 当回调中的关联的响应式对象的值改变时，会重新触发以来执行，也就是再次执行effect中传递的回调函数

接下来`src/reactivity`目录下创建`effect.ts`

```javascript
// effect.ts
// 这是所谓的依赖的核心
class ReactiveEffect {
  private _fn: any
  constructor(fn) {
    this._fn = fn
  }
  run() {
    // 这个函数会执行传递的fn，并把当前this赋值给全局activeEffect
    activeEffect = this
    this._fn()
  }
}
// 全局的对象来收集依赖，其实就是ReactiveEffect对象
let activeEffect

function effect (fn: Function ) {
  //为了更好的处理fn相关逻辑，需要一个reactiveEffect类 做抽象
  const _effect = new ReactiveEffect(fn)
  _effect.run()
}

export {
  effect,
}
```

以上就实现了effect中的回调会被立刻执行一次，接下来分析依赖收集与触发，先看我们怎么定义依赖存储的数据结构
我们现在有三级关系需要处理，对应的需要三个数据结构来存储：
`target(原始对象) -> key(原始对象的key) -> deps(依赖对象，即上面的activeEffect全局对象)`

1. 对于`target -> key`的关系我们只能使用`Map或者WeakMap`数据结构来存储，这两种数据结构的key可以是对象，但`WeakMap`得key只能是对象，而普通`object`的`key`只能是`string`或者`Symbol`，
2. 第一层`map`的`value`是代表`key -> deps`的关系，也必须要用`map`来存储
3. 对于`deps`来说，存在多个依赖但是必须不能重复，我们直接使用`Set`数据结构存储。
以上就是三层数据结构的选择，用一个简图描述的话就是：

```javascript
{
  {'foo': foo, 'foo2': foo2} : {
    'foo': new Set(...),
    'foo2': new Set(...),
  }
}
```
简单概括来说就是：
- target是一个简单对象`{'foo': foo, 'foo2': foo2}`,作为第一个map的key
- value是第二个map，简单对象的key作为这个map的key
- 第二个map的value就是存储`activeEffect全局对象`的set

现在我们可以实现`track`函数了：

```javascript
// effect.ts

// 构建第一层Map，最外层的全局变量
let targetMap = new WeakMap()
function track(target, key) {
  let depsMap = targetMap.get(target)

  if (!depsMap) {
    // 构建第2层Map
    depsMap = new WeakMap()
    targetMap.set(target, depsMap)
  }

  let depsSet = depsMap.get(key)
  if (!depsSet) {
    // 构建第3层Set
    depsSet = new Set()
    depsSet.set(key, depsSet)
  }

  depsSet.add(activeEffect)
}
```

收集完依赖后，我们触发依赖时就是三层层层递进的去获取`activeEffect`，并最终执行这个实例上的run方法，就相当于再次执行了`effect中的fn`

```javascript
// effect.ts

function trigger(target, key) {
  const depsMap = targetMap.get(target)
  // 如果这里都找不到第二层的依赖Map肯定是前面逻辑有问题
  if (!depsMap) {
    throw new Error(`${JSON.stringfy(target)}`的依赖找不到)
  }

  const depsSet = depsMap.get(key)
  // 遍历set，执行存储的activeEffect的run方法
  for(let activeEffect of depsSet) {
    activeEffect.run()
  }
}
```