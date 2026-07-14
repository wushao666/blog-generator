---
title: "手写vue3-06实现ref、isRef、unRef、proxyRefs"
date: 2022-04-18T14:31:28+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---
本节我们要实现一个超级重要的响应式操作-`ref()`，它是比响应式核心中的`reactive()`使用的更为频繁的一个操作，真正的`vue3开发`中我们也是会经常看到`ref`的身影，主要是因为`reactive()`有一定的[局限性](https://cn.vuejs.org/guide/essentials/reactivity-fundamentals.html#limitations-of-reactive)：
> 1. 仅对对象类型有效，对于基本类型`string boolean number`类型无效
> 2. 因为`vue3响应式系统`需要通过属性访问进行追踪，因此我们必须始终保持对该响应式对象的相同引用。这意味着我们不可以随意地“替换”一个响应式对象，因为这将导致对初始引用的响应性连接丢失：

## 实现`ref`


```javascript
let state = reactive({ count: 0 })

// 上面的引用 ({ count: 0 }) 将不再被追踪（响应性连接已丢失！）
state = reactive({ count: 1 })
```

> 同时这也意味着当我们将响应式对象的属性赋值或解构至本地变量时，或是将该属性传入一个函数时，我们会失去响应性：

```javascript
const state = reactive({ count: 0 })

// n 是一个局部变量，同 state.count
// 失去响应性连接
let n = state.count
// 不影响原始的 state
n++

// count 也和 state.count 失去了响应性连接
let { count } = state
// 不会影响原始的 state
count++

// 该函数接收一个普通数字，并且
// 将无法跟踪 state.count 的变化
callSomeFunction(state.count)
```
这种限制主要是因为js本身并没有提供可以作用与所有类型的一个`引用机制`，所以我们需要自己实现这样的一种引用机制，也就是`ref()`出现的背景，它可以为所有的类型提供响应式， 我们先看一下测试用例：

```typescript
import { effect } from "../effect";
import { ref } from "../ref";


describe("ref", () => {
  it("happy path", () => {
    const a = ref(1);
    expect(a.value).toBe(1);
  });

  it("should be reactive", () => {
    const a = ref(1);
    let dummy;
    let calls = 0;
    effect(() => {
      calls++;
      dummy = a.value;
    });
    expect(calls).toBe(1);
    expect(dummy).toBe(1);
    a.value = 2;
    expect(calls).toBe(2);
    expect(dummy).toBe(2);
    // same value should not trigger
    a.value = 2;
    expect(calls).toBe(2);
    expect(dummy).toBe(2);
  });

  it("should make nested properties reactive", () => {
    const a = ref({
      count: 1,
    });
    let dummy;
    effect(() => {
      dummy = a.value.count;
    });
    expect(dummy).toBe(1);
    a.value.count = 2;
    expect(dummy).toBe(2);
  });
});
```

分析一下可以发现`ref()`需要：
1. 接受任意类型数据，返回一个响应式对象，只有一个value属性，这个value属性值也是响应式的，也就是说读取value属性时，收集依赖
2. value属性修改后也会触发effect的fn，修改value属性时触发依赖
3. 相同值重复设置，不会触发

### 重构`effect`
`ref()`也需要用到响应式核心中的核心`effect`，为了和reactive业务逻辑解耦，我们需要先重构一下`effect.ts`

```typescript
// effect.ts
import { extend } from '../shared/index'

let shouldTrack
let activeEffect

class ReactiveEffect {
  private _fn: any
  public scheduler: any
  deps = []
  isStop?: () => void
  isActive = true

  constructor(fn, scheduler) {
    this._fn = fn
    this.scheduler = scheduler
  }

  run() {
    if(!this.isActive) {
      return this._fn()
    }

    activeEffect = this
    shouldTrack = true
    const result = this._fn()
    // 执行完了之后重置shouldTrack
    shouldTrack = false

    return result
  }

  stop() {
    if(this.isActive) {
      cleanEffect(this)
      if (this.onStop && typeof this.onStop === 'function') {
        this.onStop()
      }
      this.isActive = false
    }
  }
}

function cleanEffect(effect) {
  effect.deps.forEach((dep: Set<ReactiveEffect>) => {
    dep.delete(effect)
  })
}
let targetMap = new WeakMap()
function track(target, key) {
  if(!isTracking()) return
  let depsMap = targetMap.get(target)
  if (!depsMap) {
    depsMap = new WeakMap()
    targetMap.set(target, depsMap)
  }

  let depsSet = depsMap.get(key)
  if(!depsSet) {
    depsSet = new Set()
    depsMap.set(key, depsSet)
  }

  // 📢注意注意
  // 📢注意注意
  // 📢注意注意
  // 这里就是收集effect的核心依赖逻辑，抽离出去进行重构
  // depsSet.add(activeEffect)
  // // 反向收集依赖，为stop时effect删除用
  // activeEffect.deps.push(depsSet)
  trackEffects(depsSet)
}

function trackEffects(depsSet: Set<any>) {
  depsSet.add(activeEffect)
  // 反向收集依赖，为stop时effect删除用
  activeEffect.deps.push(depsSet)
}


function trigger(target, key) {
  const depsMap = targetMap.get(target) 
  if (!depsMap) {
    // 理论上必须要有这个map，没有就是大bug
    throw new Error('找不到依赖')
  }
  const depsSet = depsMap.get(key)

  //📢注意
  //📢注意
  //📢注意
  //📢注意
  //📢注意
  // 这里执行真正的依赖中的run方法抽离出去
  // for(const effect of depsSet) {
  //   if(effect.scheduler) {
  //     effect.scheduler()
  //   } else {
  //     effect.run()
  //   }
  // }
  triggerEffects(depsSet)
}

function triggerEffects(depsSet: Set<any> {
  for(const effect of depsSet) {
    if(effect.scheduler) {
      effect.scheduler()
    } else {
      effect.run()
    }
  }
})
function isTracking() {
  return shouldTrack && typeof activeEffect !== 'undefined'
}
function effect(fn, options) {
  const _effect = new ReactiveEffect(fn, options.scheduler)
  extend(_effect, options) //聚合属性

  //默认执行一次run
  _effect.run()
  const runner = _effect.run.bind(_effect) // 绑定this
  runner.effect = _effect // 为stop中的runner对象正确取到effect

  return runner
}

function stop(runner) {
  runner.effect.stop()
}

export {
  effect,
  track,
  trigger,
  stop,
  ReactiveEffect,
  isTracking,
  triggerEffects,
  trackEffects,
}
```

最终经过我们的改造，抽离出两个公共函数`trackEffects triggerEffects`, 所有的响应式数据都用这两个进行核心依赖的收集与触发。

### 实现`ref`

`ref()`模块本质上和`reactive()响应式模块一样`，区别主要在于 它返回一个只有value属性的对象，并且这个也是被`reactive()包装后的对象`，接下来我们完善细节：

```typescript
// ref.ts
import {trackEffects, triggerEffects, ReactiveEffect, isTracking} from './effect'

class RefImpl {
  private _value: any
  private _rawValue: any
  deps: Set<ReactiveEffect>;
  constructor(value) { 
    // 将对象转换 
    this._value = convert(value)
    // 存储原始值做备份
    this._rawValue = value
    this.deps = new Set()
  }

  public get value(): any {
    // 获取value属性时触发这里,收集依赖
    trackRefValue(this)
    // 返回包裹后的对象
    return this._value
  }

  public set value(newValue: any) {
    // 判断前后是不是一个值，是一个值就不需要执行
    if (hasChanged(newValue, this._rawValue)) {
      // 设置之后更新原始值
      this._rawValue = newValue
      // 设置value真正的值
      this._value = convert(newValue)
      // 触发依赖，执行effect中的fn
      triggerEffects(this.deps)
    }
  }
}

function trackRefValue(ref: RefImpl) {
  // 可以收集才收集
  if(isTracking()) {
    trackEffects(ref.deps)
  }
}
// 转换对象，是个对象就用reactive进行包裹，不是就直接返回
function convert(val) {
  return isObject(val) ? reactive(val) : val
}
function ref(raw) {
  return new RefImpl(raw)
}

```

同时在`shared/index.ts`中增加了判断对象是否变化的工具函数:

```typescript
// shared/index.ts
function hasChanged(new, old) {
  return !Object.is(new, old)
}

export {
  hasChanged
}
```

## 实现`isRef和unRef`

本节我们再次实现关于ref的工具函数，先看新增的测试用例:

```typescript
// ref.spec.ts
it('should isRef', () => {
  const a = ref(1)
  const user = reactive({
    age: 1
  })

  expect(isRef(a)).toBe(true)
  expect(isRef(1)).toBe(false)
  expect(isRef(user)).toBe(false)
});
it("should unRef", () => {
  const a = ref(1);
  expect(unRef(a)).toBe(1);
  expect(unRef(1)).toBe(1);
});
```

分析这两个新增的case，可以发现：
1. `isRef`就是判断这个对象是不是由`ref()`创建的对象
2. `unRef`就是解包，相当于直接去获取value了

```typescript
// ref.ts
class RefImpl {
  // 新增属性
  public __v_isRef = true
}

// 判断是不是ref就看有没有这个属性即可
function isRef(ref) {
  // !!避免undefined的影响
  return !!ref.__v_isRef
}

// 先判断是不是ref得，再解包
function unRef(ref) {
  return isRef(ref) ? ref.value : ref
}

export {
  isRef,
  unRef,
}
```

### 实际开发中的注意事项
在实际`vue3`项目开发中，`template`中的ref对象会被自动解包，不需要.value操作，但是注意📢：
- 仅当 ref 是模板渲染上下文的顶层属性时才适用自动“解包”。 例如， foo 是顶层属性，但 object.foo 不是。

```html
<script setup>
import { ref } from 'vue'
const count = ref(0)
</script>
<template>
{{ count }} <!-- 不需要count.value了-->
</template>
```
```javascript
// 但是
const object = { foo: ref(1) }

// 在模版中不能这样写了
{{ object.foo + 1 }} // 会打印出[object Object]

// 因为foo不是顶层属性了
// 可以改为：
const { foo }= object
{{ foo + 1}}
```

同时ref会在被reactive包裹后自动解包

```javascript
const a = ref(0)
const b = reactive({
  a
})
console.log(b.a) // 直接打印出0了
```

> 当 ref 作为响应式数组或像 Map 这种原生集合类型的元素被访问时，不会进行解包。

```javascript
const books = reactive([ref('Vue 3 Guide')])
// 这里需要 .value
console.log(books[0].value)

const map = reactive(new Map([['count', ref(0)]]))
// 这里需要 .value
console.log(map.get('count').value)
```
那么上面为什么可以不用.value，自动解包呢，继续往下实现`proxyRefs`

## 实现`proxyRefs`
`proxyRefs()`就是代理ref，帮你直接返回.value的操作，先看测试用例：

```typescript
// ref.spec.ts 新增
it("proxyRefs", () => {
  // 代理refs就是template里面不需要.value的原因
  const user = {
    age: ref(10),
    name: "xiaohong",
  };

  const proxyUser = proxyRefs(user);
  expect(user.age.value).toBe(10);
  expect(proxyUser.age).toBe(10); // 一旦被代理过就不需要再获取.value属性了
  expect(proxyUser.name).toBe("xiaohong");

  proxyUser.age = 20;

  expect(proxyUser.age).toBe(20);
  expect(user.age.value).toBe(20);

  proxyUser.age = ref(10);
  expect(proxyUser.age).toBe(10);
  expect(user.age.value).toBe(10);
});
```
分析测试用例可以知道：
1. get的时候，如果是ref，直接返回.value，如果不是ref，直接返回value即可，也就是之前实现的unRef()
2. set的时候，先判断原来是什么类型，新设置的是什么类型，如果原来是ref，设置了普通值，直接替换，如果是ref，就返回值

```typescript
// ref.ts 新增

function proxyRefs(objectWithRefs) {
  return new Proxy(objectWithRefs, {
    get(target, key) {
      const value = Reflect.get(target, key)
      return unRef(value)
    },
    set(target, key, value) {
      const oldValue = target[key]
      const result = Reflect.set(target, key, value)
      if(isRef(oldValue) && !isRef(value)) {
        // 原来是ref，新设置的不是ref的类型
        // 直接设置原来ref.value为新的值
        return target[key].value = value
      } else {
        // 新设置的一个新的ref对象，就直接替换就行
        return result
      }
    }
  })
}

export {
  proxyRefs,
}
```