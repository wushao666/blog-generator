---
title: "手写miniVue3-02实现effect的runner-scheduler-stop功能"
date: 2022-10-09T11:58:26+08:00
draft: false

tags: ["vue3"]
categories: ["vue"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

## 实现`effect`的`runner`
前面[一节](https://vvushaolin.com/post/mini-vue3%E5%AE%9E%E7%8E%B0-01%E5%AE%9E%E7%8E%B0effect%E5%92%8Creactive/)，已经实现了基础版的`reactive`和`effect`，但是vue3的`effect`实际上还有另外三种副作用，分别是`runner scheduler stop`，我们首先来实现`runner`。
先看一个测试用例新增内容：

```javascript
// effect.spec.ts 新增
it("should return runner when call effect", () => {
  // effect 执行完应该返回一个runner
  // runner执行的时候会重新执行run函数
  // 这个runner执行传进去的fn,并返回fn执行完的值
  let foo = 1

  const runner = effect(() => {
    foo++
    return foo
  })
  expect(foo).toBe(2)
  runner()
  expect(foo).toBe(3)
  expect(runner()).toBe(4)
})
```
通过测试用例很明显可以发现：
1. effect函数有一个返回值，也是所谓的runner函数
2. runner函数再次执行，又会执行effect传入的fn函数，并且能够返回fn函数的返回值，也就是说会再次执行run函数，但是run是属于`reactiveEffect的实例方法`， 所以我们首先要给runner绑定this为effect中new出来的`那个reactiveEffect实例`

```javascript
// effect.ts 

class ReactiveEffect {
  private _fn: any
  constructor(fn) {
    this._fn = fn
  }

  run() {
    activeEffect = this
    // 执行runner其实就是执行传进来的fn，并返回他的返回值
    return this._fn()
  }
}

function effect(fn: Function) {
  const _effect = new ReactiveEffect(fn)
  const runner = _effect.run.bind(_effect)

  return runner
}
```

## 实现`effect`的`scheduler`

`scheduler`调度器是一个很重要的副作用，可以在其中做一些其他的操作，它是effect
的第二个参数`options`，先看新增的测试用例：

```javascript
// effect.spec.ts
it('could have a scheduler when call effect', () => {
  // 1. effect可以接受一个options
  // 2. options中有一个函数scheduler
  // 3. 第一次effect默认执行run函数，但是scheduler不执行
  // 4. 响应式数据 update后 不会执行run函数了，只会触发 scheduler 一次
  // 5. 手动run之后，数据才会真正更新
  let dummy
  let run: any
  const scheduler = jest.fn(() => {
    run = runner
  })
  const obj = reactive({
    'foo': 1
  })
  const runner = effect(
    () => {
      dummy = obj.foo
    },
    { scheduler }
  )
  expect(scheduler).not.toHaveBeenCalled()
  expect(dummy).toBe(1)
  // 响应式数据更新后，scheduler才调用1次
  obj.foo++
  expect(scheduler).toHaveBeenCalledTimes(1)
  // 数值没有更新
  expect(dummy).toBe(1)
  // 手动run后数据才更新
  run()
  expect(dummy).toBe(2)
});
```

可以发现这个`scheduler`有以下特点：
1. 属于`effect`的第二个形参
2. 第一次effect默认执行run函数，但是scheduler不执行
3. 响应式数据 update后 不会执行run函数了，只会触发 scheduler 一次，也就是在trigger中修改
4. 手动run之后，数据才会真正更新

```javascript
// effect.ts 修改如下
class ReactiveEffect {
  private _fn: any
  public scheduler: any
  constructor(fn, scheduler) {
    this._fn = fn
    this.scheduler = scheduler
  }

  run() {
    activeEffect = this
    return this._fn()
  }
}

function trigger(target, key) {
  const depsMap = targetMap.get(target)
  if(!depsMap) {
    throw new Error(`${JSON.stringfy(target)}找不到相关依赖`)
  }
  const depsSet = depsMap.get(key)
  for(const activeEffect of depsSet) {
    if(activeEffect.scheduler) {
      activeEffect.scheduler()
    } else {
      activeEffect.run()
    }
  }
}

function effect(fn: Function, options) {
  const { scheduler } = options
  const _effect = new ReactiveEffect(fn, scheduler)

  const runner = _effect.run.bind(_effect)
  return runner
}
```

## 实现`effect`的`stop`
effect中可以停止effect的执行，先看一下新增的测试用例：

```javascript
// effect.spec.ts
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
  obj.foo = 3;
  expect(dummy).toBe(2);
  runner()
  expect(dummy).toBe(3)
});
it('should have a onstop function when call effect', () => {
  let dummy
  const obj = reactive({
    'foo': 1
  })
  const onStop = jest.fn()
  const runner = effect(
    () => {
      dummy = obj.foo
    },
    { onStop }
  )
  // stop触发时，可以接受onStop的回调
  stop(runner)
  expect(onStop).toBeCalledTimes(1)
});
```

通过分析测试用例，可以知道：
1. effect的stop就是要清理掉对应的effect，它接受一个runner作为参数，所以我们可以为runner对象把绑定this的那个effect绑定为一个新属性
2. 更为合理的就是 stop执行是就是执行上面runner对象新增的effect的stop方法，也就是为ReactiveEffect类新增方法
3. 为了能收集到所有的deps中的effect，要在track时反向收集activeEffect到ReactiveEffec类中
4. effect的第二个形参，还可以接受stop的监听`onStop`

```javascript
// effect.ts 修改如下
class ReactiveEffect {
  private _fn: any
  public scheduler: any

  onStop?: () => void // stop的回调
  deps = [] //反向存储所有依赖
  isActive = true // stop执行的标志，不能反复stop

  constructor(fn, scheduler) {
    this._fn = fn
    this.scheduler = scheduler
  }

  run() {
    activeEffect = this
    return this._fn()
  }

  stop() {
    if(this.isActive) {
      cleanEffect(this)
      // 如果传递了stop的监听函数，则在这里执行
      if(this.onStop && typeof this.onStop === 'function') {
        this.onStop()
      }

      this.isActive = false
    }
  }
}

function cleanEffect(effect) {
  // 在trigger中为其挂载的deps
  effect.deps.forEach((dep: any) => {
    // dep就是那个set
    dep.delete(effect)
  })
}

let targetMap = new WeakMap()
function track(target, key) {
  let depsMap = targetMap.get(target)
  if(!depsMap) {
    depsMap = new WeakMap()
    targetMap.set(target, depsMap)
  }

  let depsSet = depsMap.get(key)
  if(!depsSet) {
    depsSet = new Set()
    depsMap.set(key, depsSet)
  }
  //加上异常处理
  if (!activeEffect) {
    throw new Error(`activeEffect: ${activeEffect}`不存在)
  }
  depsSet.add(activeEffect)
  // 把第三层Set直接添加到activeEffect的deps属性里
  activeEffect.deps.push(depsSet)
}

function effect(fn, options = {}) {
  const _effect = new ReactiveEffect(fn)
  // options对象可能有很多属性，直接聚合到_effect对象上
  extend(_effect, options)

  const runner = _effect.run.bind(_effect)
  // 为runner增加新属性effect，这样下面的全局stop函数就能正确使用effect了
  runner.effect = _effect
  return runner
}

function stop(runner) {
  runner.effect.stop()
}
```

可以看到上面有个新增的extend函数，这个是全局工具类，在`src`下创建shared目录，创建`index.ts`

```javascript
// src/shared/index.ts

const extend = Object.assign

export {
  extend
}
```