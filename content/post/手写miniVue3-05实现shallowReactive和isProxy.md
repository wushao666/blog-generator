---
title: "手写miniVue3-05实现shallowReactive和isProxy"
date: 2022-10-10T10:07:06+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

## 实现`shallowReactive shallowReadonly`
照旧，我们先来看看测试用例，要做什么：

```typescript
// shallowReactive.spec.ts
import { isReactive, shallowReactive } from "../reactive";
describe("shallowReactive", () => {
  test("should not make non-reactive properties reactive", () => {
    const props = shallowReactive({ n: { foo: 1 } });
    expect(isReactive(props)).toBe(true);
    expect(isReactive(props.n)).toBe(false);
  });

});

// shallowReadonly.spec.ts
import { isReadonly, shallowReadonly } from "../reactive";

describe("shallowReadonly", () => {
  test("should not make non-reactive properties reactive", () => {
    const props = shallowReadonly({ n: { foo: 1 } });
    expect(isReadonly(props)).toBe(true);
    expect(isReadonly(props.n)).toBe(false);
  });

  it("should call console.warn when set", () => {
    console.warn = jest.fn();
    const user = shallowReadonly({
      age: 10,
    });

    user.age = 11;
    expect(console.warn).toHaveBeenCalled();
  });
});
```
通过分析我们发现：
1. 所谓的`shallowReactive shallowReadonly`，就是浅响应，不需要深层次响应，也就是咱们一开始实现的那种就是，只需要响应式包装最外层对象即可
2. 鉴于我们之前已经使用`baseHandler.ts`改造了响应式，所以需要在`createGetter`中做拦截

```typescript
// baseHandler.ts 修改
const getShallowReactive = createGetter(false, true)
const getShallowReadonly = createGetter(true, true)

function createGetter(isReadonly: boolean = false, isShallow: boolean = false) {
  return function get(target, key) {
    const value = Reflect.get(target,key)

    if (isShallow) {
      return value
    }

    if (key === ReactiveFlags.IS_READONLY) {
      return isReadonly
    } else if (key === ReactiveFlags.IS_REACTIVE) {
      return !isReadonly
    }

    if (isObject(value)) {
      return isReadonly ? readonly(value) : reactive(value)
    }

    if (!isReadonly) {
      trigger(target, key)
    }
    return value
  }
}

const mutableHandlerShallowReactive = {
  get: getShallowReactive,
  set,
}

const mutableHandlerShallowReadonly = {
  get: getShallowReadonly,
  set(target, key, value) {
    
     console.warn(`key :"${String(key)}" set 失败，因为 target 是 readonly 类型`, target);
    return true

  }
}

export {
  mutableHandlerShallowReactive,
  mutableHandlerShallowReadonly,
}

// reactive.ts
import { mutableHandlerShallowReactive, mutableHandlerShallowReadonly} from ./baseHandler.ts

function shallowReactive(raw: Object) {
  return createActiveObject(raw, mutableHandlerShallowReactive)
}

function shallowReadonly(raw: Object) {
  return createActiveObject(raw, mutableHandlerShallowReadonly)
}

function createActiveObject(target, baseHandler) {
  return new Proxy(target, baseHandler)
}

export {
  shallowReactive,
  shallowReadonly,
}
```

## 实现`isProxy`
本节实现一个响应式工具类：`isProxy`，先看测试用例的更新：

```typescript
// reactive.spec.ts
describe("reactive", () => {
  it("happy path", () => {
    describe("reactive", () => {
      expect(isReactive(observed.nest)).toBe(true)
      expect(isReactive(observed.arr)).toBe(true)
      expect(isReactive(observed.arr[0])).toBe(true)

      // 新增
      expect(isProxy(observed)).toBe(true)
    })
  })
}

// readonly.spec.ts
it('happy path', () => {
  describe("readonly", () => {
    expect(isReadonly(observed.nested)).toBe(true)
    expect(isReadonly(observed.arr)).toBe(true)
    expect(isReadonly(observed.arr[0])).toBe(true)

    // 新增
    expect(isProxy(observed)).toBe(true)
  });
}
```

其实一分析就发现它就是判断对象是不是被代理过，也就是说它是之前我们实现的`isReadonly isReactive`的并集

```typescript
// reactive.ts

function isProxy(raw) {
  return isReactive(raw) || isReadonly(raw)
}

export {
  isProxy
}
```