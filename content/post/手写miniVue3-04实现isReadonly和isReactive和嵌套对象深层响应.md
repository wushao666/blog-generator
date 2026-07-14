---
title: "手写miniVue3-04实现isReadonly和isReactive"
date: 2022-03-31T17:24:00+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

这两个属于响应式的工具类，判断是属于哪种类型的响应式对象.
- isReactive(target): 判断对象是否由 reactive() 创建的响应式代理
- isReadonly(target): 判断对象是否由 readonly() 创建的响应式代理

<!-- more -->

## 实现`isReadonly`和`isReactive`
照旧先看测试用例：

```javascript
// reactive.spec.ts 新增
expect(isReactive(observed)).toBe(true)
expect(isReactive(origin)).toBe(false)

// readonly.spec.ts 新增
expect(isReadonly(observed)).toBe(true)
expect(isReadonly(origin)).toBe(false)
```
这两个新增的测试用例都很简单，下面我们想象应该咋实现这两个判断方法。

```javascript
// reactive.ts 新增
// 我们的思路是通过两个新增的key来判断属于哪种，当我们触发get操作时，就可以返回结果了

enum ReactiveFlags {
  IS_REACTIVE = '__v_isReactive',
  IS_READONLY = '__v_isReadonly',
}

function isReactive(obj: Object) {
  // 双感叹号变成bool值，并能必现undefined的影响
  return !!obj[ReactiveFlags.IS_REACTIVE]
  // 这里我们回去触发get操作，在get操作中拦截这个key，并返回结果
}

function isReadonly(obj: Object) {
  // 双感叹号变成bool值，并能必现undefined的影响
  return !!obj[ReactiveFlags.IS_READONLY]
  // 这里我们回去触发get操作，在get操作中拦截这个key，并返回结果
}

export {
  isReactive,
  isReadonly
}
```

接下来我们就修改`baseHandler.ts`

```typescript
// baseHandler.ts

function createGetter(isReadonly: Boolean = false) {
  return function get(target, key) {
    if (key === ReactiveFlags.IS_READONLY) {
      return isReadonly
    } else if (key === ReactiveFlags.IS_REACTIVE) {
      return !isReadonly
    }
  }
}
```

***

## 修复`stop`后重复收集依赖的bug

让我们看一下之前的测试用例，会发现之前的代码中`stop`之后也会重复收集依赖effect，导致stop无效，我们先修复这个bug，并重新梳理一下stop的逻辑：

```javascript
// effect.spec.ts 中描述stop的那个测试逻辑
it('should have a stop function when call effect', () => {
  let dummy
  const obj = reactive({
    'foo': 1
  })
  const runner = effect(
    () => {
      dummy = obj.foo
    },
  )
  obj.foo = 2
  expect(dummy).toBe(2)
  // stop是可以阻止更新runner执行的，即清理掉effect
  stop(runner)

  //注意注意📢
  //注意注意📢
  //注意注意📢
  //注意注意📢
  //注意注意📢
  //注意注意📢
  //注意注意📢
  //注意注意📢
  // 正常来说按照我们之前的写法，直接set也是可以过测试的，
  obj.foo = 3;
  // 但是但是但是 有可能会用下面的写法，那么相当于
  // stop时清理的effect，又在get的时候被收集到了，所以又set得时候，触发trigger ，执行了run()
  // dummy会变成了 3，不是预期的2
  obj.foo++ // 等同于obj.foo = obj.foo + 1 先get再set了

  expect(dummy).toBe(2);
  runner()
  expect(dummy).toBe(3)
});
```

上面的📢那里就是bug所在，所以我们为了避免**stop后再次收集依赖的bug**，需要使用新的标志来区分：

```typescript
// effect.ts 对应修改如下

// 两个全局变量
// 标志是否应该收集
let shouldTrack
// 全局ReactiveEffect对象做依赖的核心
let activeEffect

class ReactiveEffect {
  private _fn: any
  public scheduler: any
  isActive = true
  onStop?: () => void
  deps = []
  constructor(fn, scheduler) {
    this._fn = fn
    this.scheduler = scheduler
  }

  run() {
    // 📢 如果被stop了，直接返回fn()结果
    if(!isActive) {
      return this._fn()
    }

    // 到这说明没有被stop，是effect的初始化执行
    // 赋值effect
    activeEffect = this
    // 可以被track
    shouldTrack = true
    // 执行effect传递的fn
    // 此时fn中代码逻辑会有get操作，触发trigger
    // 此时trigger中发现shouldTrack activeEffect都有值，可以正常收集依赖
    const result = this._fn()
    // 执行完fn后，不应该再收集依赖
    // 除非再次runner()，重新执行上述逻辑并开启shouldTrack
    shouldTrack = false

    // 不管怎样，run必须返回fn()的结果
    return result
  }

  stop() {
    if(this.isActive) {
      //清理effect
      cleanEffect(this)
      if(this.onStop && typeof this.onStop === 'function') {
        // effect上有stop监听则执行
        this.onStop()
      }

      // 修改this.isActive，防止重复stop
      this.isActive = false
    }
  }
}

function cleanEffect(effect) {
  effect.deps.forEach((dep: Set<ReactiveEffect>) => {
    // 清理掉真正的effect
    dep.delete(effect)
  })
}

function trigger(target, key) {
  const depsMap = targetMap.get(target) 
  // 这个Map必须有，没有就是大问题
  if(!depsMap) {
    throw new Error(`target: ${JSON.stringfy(target)}没有找到对应的依赖`)
  }

  const depsSet: Set<ReactiveEffect> = depsMap.get(key)
  for(const effect of depsSet) {
    // 如果被stop 清理掉对应的effect了，就找不到对应effect来执行
    if (effect.scheduler) {
      effect.scheduler()
    } else {
      effect.run()
    }
  }
}
function isTracking() {
  // 满足应该收集 并且 全局ReactiveEffect对象存在才可以触发track
  return shouldTrack && activeEffect !== undefined
}

let targetMap = new WeakMap()
function track(target, key) {
  if(!isTracking()) return

  // 可以被收集才进入正常逻辑
  // 先看target有没有对应的map
  let depsMap = targetMap.get(target)
  if(!depsMap) {
    // 没有则构建depsMap并设置
    depsMap = new WeakMap()
    targetMap.set(target, depsMap)
  }

  //再看有没有对应的set
  let depsSet = depsMap.get(key)
  if(!depsSet) {
    depsSet = new Set()
    depsMap.set(key, depsSet)
  }

  depsSet.add(activeEffect)

  // 为了stop时能获得effect，反向在effect的deps属性中收集depsSet
  activeEffect.deps.push(depsSet)
}
```

## 实现嵌套对象的深层相应
我们正常使用时，有时候会存在对象的value又是对象的情况，这就是所谓的嵌套对象，之前我们的实现中是无法做到深层次的响应式的：

```javascript
const obj = {
  'a': {
    'b': {
      c: [1, 2, 3]
    }
  }
}
```
先看我们的测试用例：

```typescript
// reactive.spec.ts 
it("happy path", () => {
  const origin = {
    'foo': 1,
    'nest': {
      'test': 1
    },
    'arr': [{
      test: 123
    }]
  }

  const observed = reactive(origin)
  expect(observed).not.toBe(origin)
  expect(observed.foo).toBe(1)

  // 查看某个对象是不是响应式的
  expect(isReactive(observed)).toBe(true)
  expect(isReactive(origin)).toBe(false)

  // 嵌套对象也应该是响应式
  expect(isReactive(observed.nest)).toBe(true)
  expect(isReactive(observed.arr)).toBe(true)
  expect(isReactive(observed.arr[0])).toBe(true)
})

// readonly.spec.ts 修改如下
it('happy path', () => {
  const origin = {
    foo: 1
    foo: 1,
    nested: {
      test: 12,
    },
      arr: [{
      test2: 12,
      }]
  }

  const observed = readonly(origin)
  expect(observed.foo).toBe(1)
  expect(observed).not.toBe(origin)

  expect(isReadonly(observed)).toBe(true)
  expect(isReadonly(origin)).toBe(false)

  // 嵌套对象也应该是响应式
  expect(isReadonly(observed.nested)).toBe(true)
  expect(isReadonly(observed.arr)).toBe(true)
  expect(isReadonly(observed.arr[0])).toBe(true)
});
```
可以看到我们之前实现的`isReactive和isReadonly`工具函数可以很好地检验我们的结果。
我们的实现思路是：
1. 第一层的raw对象肯定被`reactive或者readonly`，包装成了响应式对象，如果要继续读取内部的属性值，势必会触发get操作
2. 处理`baseHandler.ts`的getter值，发现是对象再判断`isReadonly`属性值包装成对象的响应式对象

```typescript
// baseHandler.ts
import { reactive, readonly, ReactiveFlags } from './reactive'
import { isObject } from './shared'
function createGetter(isReadonly: boolean = false) {
  return function get(target, key) {
    const value = Reflect.get(target, key) 
    
    // 判断是isReactive 还是isReadonly
    if (key === ReactiveFlags.IS_READONLY) {
      return isReadonly
    } else if (key === ReactiveFlags.IS_REACTIVE) {
      return !isReadonly
    }

    // 判断是否需要深层响应
    if (isObject(value)) {
      return isReadonly ? readonly(value) : reactive(value)
    }

    if (!isReadonly) {
      track(target, key)
    }

    return value
  }
}

// shared/index.ts

function isObject(obj) {
  return obj !== null && typeof obj === 'object'
}

export {
  isObject,
}
```


