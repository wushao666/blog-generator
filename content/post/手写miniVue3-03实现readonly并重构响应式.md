---
title: "手写miniVue3-03实现readonly并重构响应式模块"
date: 2022-10-09T14:59:45+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

## 重构`reactive`
本来我们应该直接实现`readonly`模块的，但是其实它本质上和`reactive`很像，只不过它是只读的，不能`set`，set时，不会设置成功只会警告，所以相似代码很多，我们开发之前先重构一下`reactive`

分析一下这个响应式场景下`proxy`的两个形参，影响最主要的是第二个参数`handler`， 也就是一个包含`get set函数的对象`

```javascript
{
  get(target, key) {},
  set(target, key, value) {},
}
```

所以我们先把这部分拆分出去，在`reactivity`目录下创建`baseHandler.ts`

```javascript
// reactive.ts 改造如下
import {
  mutableHandler,
  mutableHandlerReadonly,
} from './baseHandler'

function reactive(raw) {
  return createReactiveObject(raw, mutableHandler)
}

function readonly(raw) {
  return creativeReactiveObject(raw, mutableHandlerReadonly)
}

// 根据不同的handler统一创建代理对象，相当于中间层，解耦响应式和handler处理器
function creativeReactiveObject(target, baseHandler) {
  return new Proxy(target, baseHandler)
}
```
上面的`mutableHandler，mutableHandlerReadonly`就是要重点重构的两个函数，导出的这两个对象就是上面分析的这类对象:

```javascript
{
  get(target, key) {},
  set(target, key, value) {},
}
```

详细的代码逻辑：


```javascript
// baseHandler.ts
import { trigger, track } from './effect'

// 这样写的目的是能缓存这些函数值，只在文件初始化时加载一次即可
const get = createGetter()
const getReadonly = createGetter(true)
const set = createSetter()

function createGetter(isReadonly: Boolean = false) {
  return function get(target, key) {
    const value = Reflect.get(target, key)

    if(!isReadonly) {
      // 不是readonly才需要收集依赖
      track(target, key)
    }

    return value
  }
}

function createSetter() {
  return function set(target, key, value) {
    const value = Reflect.set(target, key, value)

    trigger(target, key)
    return value
  }
}

const mutableHandler = {
  get,
  set,
}

const mutableHandlerReadonly = {
  get: getReadonly,
  set(target, key, value) {
    console.warn(`key :"${String(key)}" set 失败，因为 target 是 readonly 类型`, `${JSON.stringfy(target)}`)
    return true
  }
}

export {
  mutableHandler,
  mutableHandlerReadonly,
}
```

## 实现`readonly`
其实经过上面的重构，我们已经实现完了`readonly`。而且后期我们实现新的代理会变的很容易，直接增加对应的`baseHandler`即可，先看一下测试用例的用法：

```javascript
import { readonly } from "../reactive";

describe("readonly", () => {
  it('happy path', () => {
    const origin = {
      foo: 1
    }

    const observed = readonly(origin)
    expect(observed.foo).toBe(1)
    expect(observed).not.toBe(origin)
  });
  it('console warn when you set value', () => {
    const origin = {
      foo: 1
    }
    console.warn = jest.fn()
    const observed = readonly(origin)
    observed.foo = 2
    expect(console.warn).toHaveBeenCalled()
  });
})
```
其实`readonly`几乎和`reactive`一样，都是响应式的，只是不能修改属性值。