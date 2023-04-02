---
title: "Javascript中的异步问题"
date: 2022-11-16T18:51:22+08:00
draft: false

tags: ["前端"]
categories: ["JavaScript"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

今天我们来聊一聊 JavaScript 中的"异步"，所谓的异步就是我不立刻等函数执行的结果，我去执行其他逻辑，当函数有了结果，再来通知我。
这个通知的动作就叫回调函数-`callback`，更准确的说这里是异步回调函数。

## 回调函数

在 JavaScript 中，回调函数处处可以见到，比如

```javascript
// 1. ajax请求
ajax(url, function () {
  // 一堆逻辑操作
});
// 2. 定时器中
setTimeout(function () {
  // 一堆逻辑操作
}, 1000);
```

通常我们不会立刻得到结果，所以我们传递一个 callback 做形参，后续逻辑可以在其中处理，但是随着逻辑的发展可能我们的回调中可能需要继续回调，例如：

```javascript
ajax(url, function () {
  // 一堆逻辑操作
  ajax(url, function () {
    // 一堆逻辑操作
    ajax(url, function () {
      // 一堆逻辑操作
    });
  });
});
```

### 回调地狱

用 nodejs 读取 📃 举个 🌰，本地新建一个 name.txt 文件，内容是字符串"./number.txt", number.txt 文件的内容又是是字符串"./score.txt"， score.txt 文件的内容是字符串 100：

```js
const fs = require("fs");

// 错误先行的策略,node中首先要处理err,这里为了方便看回调地狱就先不处理了
fs.readFile("./name.txt", "utf-8", function (err, data) {
  fs.readFile(data, "utf-8", function (err, data) {
    fs.readFile(data, "utf-8", function (err, data) {
      console.log("data is: ", data);
    });
  });
});
// 第一个data就是./number.txt，第二个data就是./score.txt，第三个data就是结果100
```

如果嵌套层次过深，会暴露出回调的两个根本问题：

1. 嵌套的层次中耦合性太重，不敢轻易动代码，牵一发动全身。
2. 嵌套的层次太多的话，错误处理不是很好处理，容易遗漏某种错误情况。
   所以社区中的人们就探索了很多优雅地异步编写代码的方式，并逐渐形成了现在的 es 规范，发展历程经历了生成器函数-`Generator`、co 模块，到如今主流的 Promise，以及最终的`async/await`，接下来我们先聊聊`Promise`

### 高阶函数

因为在`JavaScript`中，函数就是一个值，也就是一个变量对象，自然可以做为函数的形参用，所以如果形参是一个回调函数的话，那么我们就称之为高阶函数，这个概念在数组中经常看到：

```javascript
Array.prototype.map(fn);
Array.prototype.forEach(fn);
Array.prototype.reduce(fn);
Array.prototype.filter(fn);
Array.prototype.sort(fn);
```

### 异步回调函数<=>同步回调函数

通过上面的例子我们可以看到，其实有的回调函数是同步的，宿主环境知道在合适的时机执行回调，也就是同步回调函数，而像`setTimeout ajax`这里的传递的回调就被称为异步回调函数。

## Promise

既然我们说传统的回调函数有回调地狱的弊端，那么改用`Promise`改造一下，在这之前先了解一下什么事`Promise`，`Promise`是现在主流的编写异步代码的规范，常见的写法就是:

```javascript
const promiseDemo = new Promise((resolve, reject) => {
  resolve("resolve");
  // 不会执行
  reject("reject");
});
promiseDemo
  .then(
    (res) => {
      // 成功
      console.log(res); // 打印 resolve
    },
    (reason) => {
      // 失败
    }
  )
  .catch((err) => {
    // 失败
  })
  .finally(() => {
    console.log("无论怎样我都会执行");
  });
```

了解完基本用法之后，我们改造一下回调地狱：

```js
function readFile(pathname = "") {
  return new Promise(function (resolve, reject) {
    //! 用同步执行器函数 包裹 异步操作，再通过异步操作的结果来改变promise的状态
    fs.readFile(pathname, "utf-8", function (err, data) {
      if (err) {
        reject(err); // 注册promise 失败状态数据
        return;
      }
      resolve(data); // 注册promise 成功状态数据
    });
  });
}

//! promise的状态 取决于 异步任务的完成与否
// pending => fulfilled or pending => rejected
let promise = readFile("./name.txt");

//! 那么我们怎么知道异步任务的结果呢，就是通过Promise的状态来获得
//! 需要通过then的回调来获取这个状态，相当于解开了回调嵌套，把逻辑交到了then的回调里面
promise
  .then((res) => readFile(res)) // 这里的res就是number.txt
  .then((res) => readFile(res)) // 这里的res就是score.txt
  .then((res) => console.log(res)); // // 这里的res就是100
```

上面的那个改造我们可以进一步封装，把 node 风格的异步函数包装成一个返回 promise 的新的函数：

```js
// 😎 接下来我们抽象一个函数，封装异步函数，并返回一个promise
function promisify(fn = () => {}) {
  return function (...args) {
    return new Promise((resolve, reject) => {
      fn(...args, function (err, data) {
        if (err) {
          reject(err);
          return;
        }
        resolve(data);
      });
    });
  };
}

// 得这样使用了
let readFilePromisify = promisify(fs.readFile);
readFilePromisify("./name.txt", "utf-8")
  .then((res) => readFilePromisify(res, "utf-8")) // 这里的res就是number.txt
  .then((res) => readFilePromisify(res, "utf-8")) // 这里的res就是score.txt
  .then((res) => console.log("readFilePromisify 写法：", res)); //这里的res就是100
```

分析以上面的例子，总结一下 Promise 使用中的注意事项。

### Promise 的特点

首先我们先看一下它的特点有哪些，

1. `Promise`构造函数，必须接受一个函数，并且这个函数形参会立刻执行，它又有两个形参，第一个是 resolve 函数，代表成功的回调，第二个是 reject 函数，代表失败的回调
2. Promise 的状态是不可逆的，只有三种状态，初始态为 `pending`，要么变成`fulfilled`， 要么变成`rejected`，也就是上面例子中，执行完`resolve`函数后就不会执行 reject 函数，真实的属性是：
   `[[PromiseState]]: "fulfilled"`,
   `[[PromiseResult]]: resolve`
3. 上面执行的结果 PromiseResult 要想获取，需要通过 then 函数去调用，取到 resolve 中的参数，then 方法也有两个参数，第一个回调就是取 resolve 中参数的函数，第二个回调就是取 reject 中参数的回调，但是通常我们本着单一原则，错误处理统一放到 catch 方法中捕获
4. 要格外注意上面的 then 方法是返回一个 promise 的，所以可以做链式调用，它会隐式的调用静态方法 Promise.resolve 方法来包装返回值，使其成为一个合法的 Promise 对象
5. 最后还有一个重要的 finally 方法，是相当于兜底的作用，他接受一个函数做参数，但是这个函数中不接受参数

显而易见的 Promise 的优点是解决了回调地狱的层层嵌套问题，使逻辑变得更加清晰，错误也能方便的捕获到，但是它的缺点是一旦 new 了 promise 无法取消它，而且他的错误仍然是需要回调函数来处理的，当多个 then 链式调用时也是需要注意。

### promise 状态依赖问题

```js
//! 状态依赖 promise最终的状态依赖于那个注入的promise
const p1 = new Promise((resolve, reject) => {
  setTimeout(() => {
    reject("你失败了");
  }, 3000);
});
const p2 = new Promise((resolve, reject) => {
  setTimeout(() => {
    resolve(p1);
  }, 1000);
});

p2.then((res) => {
  console.log("res is: ", res);
}).catch((err) => {
  console.log("err is: ", err);
  // 只打印这里，它依赖于p1的状态的
  // err is:  你失败了
});
```

### 实用的几个静态方法

上面介绍了几个好用的实例方法，这一节带来几个好用的静态方法

1. `Promise.resolve()`，直接构建成功的 promise，如果接受一个 thenable 对象，会执行这个 thenable 对象的 then 函数
2. `Promise.reject()`，直接构建失败的 promise
3. `Promise.all()`， 接受 promise 对象组成的数组，返回数组顺序的 promise 元素 resolve 成功后的数组，但是有一个失败，直接进失败，只打印失败的 promise 的 reject 的那个结果，没有其他 promise 的成功结果。
4. `Promise.allSettled()`，接受 promise 对象组成的数组，但是无论成功失败都返回包装后的数组顺序的结果对象组成的数组
5. `Promise.race()`，接受 promise 对象组成的数组，但是返回最先执行完的那个结果，无论成功还是失败

```javascript
let p1 = new Promise((resolve, reject) => {
  setTimeout(() => {
    reject("111");
  }, 2000);
});
let p2 = new Promise((resolve, reject) => {
  setTimeout(() => {
    resolve("222");
  }, 5000);
});
let p3 = new Promise((resolve, reject) => {
  setTimeout(() => {
    resolve("333");
  }, 1000);
});

Promise.allSettled([p1, p2, p3])
  .then((res) => {
    console.log("res is", res);
    // 1. allSettled 打印如下：
    // [
    //   ({
    //     status: "rejected",
    //     reason: "111",
    //   },
    //   {
    //     status: "fulfilled",
    //     value: "222",
    //   },
    //   {
    //     status: "fulfilled",
    //     value: "333",
    //   })
    // ];
    ////////////////////////
    // 2. 但是换成all的话，执行如下：
    // err is 111
    /////////////////////////////
    // 3. 但是换成race的话，执行如下：
    // res is 333
  })
  .catch((err) => {
    console.log("err is", err);
  });
```

接下来我们实现一下这五个静态方法：

```js
Promise.allWu = function (promises = []) {
  return new Promise((resolve, reject) => {
    const result = [];
    const length = promises.length;
    let index = 0;
    if (length === 0) resolve(result);
    for (let i = 0; i < length; i++) {
      const promise = promises[i];

      Promise.resolve(promise)
        .then((res) => {
          result[i] = res;
          index++;
          if (index === length) {
            resolve(result);
          }
        })
        .catch((err) => {
          reject(err);
        });
    }
  });
};

Promise.allSettledWu = function (promises = []) {
  return new Promise((resolve, reject) => {
    const result = [];
    const length = promises.length;
    let index = 0;
    if (length === 0) {
      resolve(result);
    }

    for (let i = 0; i < length; i++) {
      const promise = promises[i];
      Promise.resolve(promise)
        .then((res) => {
          index++;
          result[i] = {
            value: res,
            status: "fulfilled",
          };
          if (index === length) {
            resolve(result);
          }
        })
        .catch((err) => {
          index++;
          result[i] = {
            reason: err,
            status: "rejected",
          };
          if (index === length) {
            resolve(result);
          }
        });
    }
  });
};

Promise.raceWu = function (promises = []) {
  return new Promise((resolve, reject) => {
    const result = [];
    const length = promises.length;
    if (length === 0) {
      resolve(result);
    }

    for (let i = 0; i < length; i++) {
      const promise = promises[i];
      Promise.resolve(promise)
        .then((res) => {
          resolve(res);
        })
        .catch((err) => {
          reject(err);
        });
    }
  });
};
```

### 判断某个对象是不是 Promise

一定要记住这个实用的 toString 方法，它是 Object 原型上的，每个不同的对象重写了这个方法，所以需要用 call 改变调用的主体去执行：
` Object.prototype.toString.call(new Promise(() => {})) === '[object Promise]'`

## `async/await`

最新的也是最棒的 👍🏻 的异步解决方案就是这两个关键字`async/await`，拆解来分析：

1. `async`加到函数前面，使其返回一个 promise 对象，默认使用 Promise.resolve()包装
2. `await`只能存在于 async 函数内部，因为这个语法糖就是`generator`和`promise`一起实现的，它使其后面的代码块变成异步微任务，也就是相当于添加到了 Promise.resolve().then()的 then 中的回调

```javascript
async function test() {
  console.log("test");
  return 2000;
}
test();
// Promise {<fulfilled>: 2000}

// 等价于 以下：//////////////
// new Promise((resolve, reject) => {
//   resolve(2000);
// });
///////////////////////////

async function getAwait() {
  const result = await test();
  console.log("result", result);
  // 等价于 以下： /////////////
  // test().then((res) => {
  //   console.log("result2", res);
  // });
}
getAwait(); // 先打印test，再打印 2000
```

这两语法糖用起来很简单，但是接下来我们还是要分析一下它的深层次的原理的，这之前就要隆重介绍一下生成器`Generator`了。

## 生成器`Generator`

生成器-`Generator`是一个比较棘手的问题，探讨他之前，我们可以来复习一下其他的入门小知识增强一下自信:)

### 遍历和迭代

先复习一下基本数据结构的遍历：

```javascript
let arr = [1, 2, 3, 4];
let str = "5678";
let obj = {
  a: 9,
  b: 10,
  c: 11,
  d: 12,
};

// 数组也可以用forEach
for (let i = 0; i < arr.length; i++) {
  console.log(`arr-${i}= ${arr[i]}`);
}

for (let i = 0; i < str.length; i++) {
  console.log(`str-${i}= ${str[i]}`);
}

for (let i in obj) {
  console.log(`obj-${i}= ${obj[i]}`);
}
```

可以看到其实不同的数据结构遍历的方式是不同的，可能会造成混乱，那么能不能用一种方式来遍历所有的数据结构呢，所以我们来介绍一下`for...of`迭代，它是按顺序的抽取连续元素的一种方式：

```js
let arr = [1, 2, 3, 4];
let str = "5678";
let obj = {
  a: 9,
  b: 10,
  c: 11,
  d: 12,
};
for (let i of arr) {
  console.log(`${i}`);
}

for (let i of str) {
  console.log(`${i}`);
}

// 这里会报错 Uncaught TypeError: obj is not iterable
for (let i of obj) {
  console.log(`${i}`);
}
```

这里的 obj 报错主要是因为他不是可迭代的，也就是没有实现`Symbol.iterator`方法：
![](/images/js/iterator.jpg)

### 迭代器

上一节那个核心方法的特点是：返回一个迭代器对象，该对象有一个 next 方法，我们可以试试这个方法：

```js
let arr = [1, 2, 3, 4];

let iter = arr[Symbol.iterator]();
console.log("iter is: ", iter); // Array Iterator {}
console.log("iter.next(): ", iter.next());
// {
//     "value": 1,
//     "done": false
// }
console.log("iter.next(): ", iter.next());
// {
//     "value": 2,
//     "done": false
// }
console.log("iter.next(): ", iter.next());
// {
//     "value": 3,
//     "done": false
// }
console.log("iter.next(): ", iter.next());
// {
//     "value": 4,
//     "done": false
// }
console.log("iter.next(): ", iter.next());
// {
//     "value": undefined,
//     "done": true
// }
```

可以发现 4 个元素，next()执行了四次，都是返回 done 是 false 的对象，也就是没迭代完，第五次迭代完了，done 是 true，这就是`for...of`的原理
那么我们手写一下这个`Symbol.iterator`函数

```js
Array.prototype.myIterator = function () {
  const that = this;
  let index = 0;
  return {
    next() {
      if (index < that.length) {
        return {
          value: that[index++], // 先取值，再把index递增
          done: false,
        };
      } else {
        return {
          value: undefined,
          done: true,
        };
      }
    },
  };
};
let arr = [1, 2, 3, 4];
let iter = arr.myIterator();
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
// 和上面原生的方法打印是一样的
```

那么我们也**改造一个可迭代的 obj**

```js
let obj = {
  a: 1,
  b: 2,
  c: 3,
  d: 4,
  [Symbol.iterator]: function () {
    let index = 0;
    // 因为obj天然不是有序且连续的，借用map改造
    const map = new Map();
    map.set("a", 1);
    map.set("b", 2);
    map.set("c", 3);
    map.set("d", 4);
    // map是塞进去一个二维数组的，上面四行等价于
    // const map = new Map([
    //   ["a", 1],
    //   ["b", 2],
    //   ["c", 3],
    //   ["d", 4],
    // ]);
    // 再转化成一个数组存
    const arr = [];
    for (let i of map) {
      // i 就是 ['a', 1]这种的
      arr.push(i);
    }
    return {
      next() {
        if (index < arr.length) {
          return {
            value: arr[index++], // 先取值，再把index递增
            done: false,
          };
        } else {
          return {
            value: undefined,
            done: true,
          };
        }
      },
    };
  },
};

let iter = obj[Symbol.iterator]();
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
```

所谓的迭代器就是实现了上述迭代器协议的一类对象。
我们虽然改造完了，但是发现每次这样操作好麻烦啊，能不能有一种省劲的办法呢，😄 当然是有了，那就是用生成器去生成迭代器，它天然就能被`for...of`迭代

### 生成器

经过前面的实践，终于到了我们的中心话题-生成器，先看一个简单的示例：

```js
function* testGenerator() {
  yield 1;
  yield 2;
  yield 3;
  yield 4;
}

const iter = testGenerator();
console.log("iter is: ", iter);
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
```

我们发现这和之前的实现是一样的，所以可以用`for...of`

```js
function* testGenerator() {
  yield 1;
  yield 2;
  yield 3;
  yield 4;
}

const iter = testGenerator();
for (let i of iter) {
  console.log(i);
}
```

进一步的我们分析一下他的特点：

```js
//// 使用return
// 1. 写法
function* testGenerator() {
  // 2. 中断函数执行
  let a = yield 1;
  console.log("a is ", a);
  return 2;
  let b = yield 2;
  console.log("b is ", b);
  let c = yield 3;
  console.log("c is ", c);
  let d = yield 4;
  console.log("d is ", d);
}

const iter = testGenerator();
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
// 到这的时候，return也会终止，把done置为true，所以后面的next都拿不到值了，通常不在生成器中使用return
// iter.next():  {value: 2, done: true}
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());

//////////不使用return, next方法传值
function* testGenerator() {
  // 2. 中断函数执行
  let a = yield 1;
  console.log("a is ", a); // 打印222
  let b = yield 2;
  console.log("b is ", b); // 打印333
  let c = yield 3;
  console.log("c is ", c); // 打印444
  let d = yield 4;
  console.log("d is ", d); // 打印555
}

const iter = testGenerator();
console.log("iter.next(): ", iter.next(111));
console.log("iter.next(): ", iter.next(222));
console.log("iter.next(): ", iter.next(333));
console.log("iter.next(): ", iter.next(444));
console.log("iter.next(): ", iter.next(555));、

//////////不使用return, next方法不传值
function* testGenerator() {
  // 2. 中断函数执行
  let a = yield 1;
  console.log("a is ", a); // 打印undefined
  let b = yield 2;
  console.log("b is ", b); // 打印333
  let c = yield 3;
  console.log("c is ", c); // 打印444
  let d = yield 4;
  console.log("d is ", d); // 打印555
}

const iter = testGenerator();
console.log("iter.next(): ", iter.next(111));
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next(333));
console.log("iter.next(): ", iter.next(444));
console.log("iter.next(): ", iter.next(555));
```

还记得前面我们实现的那个可迭代的对象吗，既然我们的生成器能生成迭代器，自带 next 方法，那么我们用生成器改造一下，会变得更简单：

```js
let obj = {
  a: 1,
  b: 2,
  c: 3,
  d: 4,
  [Symbol.iterator]: function* () {
    let index = 0;
    // 因为obj天然不是有序且连续的，借用map改造
    const map = new Map();
    map.set("a", 1);
    map.set("b", 2);
    map.set("c", 3);
    map.set("d", 4);
    const resultArr = [...map.entries()];
    while (index < resultArr.length) {
      yield resultArr[index++];
    }
  },
};

let iter = obj[Symbol.iterator]();
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
console.log("iter.next(): ", iter.next());
// 这里将不会报错
for (let i of obj) {
  console.log("i is: ", i);
}
```

### 生成器的特点

总结一下生成器的特点：

1. function 关键字后面加一个`*`
2. 它可以中端函数的执行，类似于 return，但是生成器函数最好使用`yield`关键字产出一个值
3. 通过 next 方法来获取中断的值
4. next()可以传值，第一个 next 方法传的会被忽略，从第二传的值开始，会赋值给第一个 yield 表达式的返回值。
5. 如果 next 方法不传值，那么 yield 表达式的返回值就是 undefined

可以看到这个 next 传值和 yield 表达式返回不符合常理，很难理解，那么我们继续改造：使其返回值就是当前的值，也就是`co模块`封装的道理

### `co模块`

我们还是借用 Promise 那一章开头封装好的的`readFile()`，它返回一个包装了 node 异步读取文件的原生`readFile()`的 Promise，我们想利用生成器函数，不想.then 三次那样使用：

```js
function* generatorFunc() {
  let number = yield readFile("./name.txt"); // 这个地方yield期待返回 "./number.txt", 作为下一个readFile的参数
  let score = yield readFile(number); // 这个地方yield期待返回 "./score.txt",作为下一个readFile的参数
  let result = yield readFile(score); // 这个地方yield期待返回 score.txt 文件中的 结果：100

  console.log("result", result); // 这里就应该是100
}
//! 要想实现上面的期待的结果，只有生成器是办不到的，但是可以利用生成器next的独特之处 + 一个执行器函数 😎

let iter = generatorFunc();
const { value, done } = iter.next(); // 第一次next 目的是为了拿到初始化的promise
//! 先实现一版粗糙的执行器函数，一步一步执行，总共执行3次.then，再调用三次next()，传值进去
value.then((res) => {
  // res ./number.txt
  const { value, done } = iter.next(res);
  value.then((res) => {
    // res ./store.txt
    const { value, done } = iter.next(res);
    value.then((res) => {
      // res 100
      const { value, done } = iter.next(res); // 最后把100塞到第四个next里面，因此第三个yield表达式就能拿到结果了，直接return
      // 此时done为true，这个res就是我们需要的值
    });
  });
});
```

还记得上一节中 next 方法的奇怪特性吗：

1. 第一个 next()传参会被忽略
2. 后续 next()传参会设置到对应位次减一的 yield 表达式的返回值

上面的执行器核心就是利用了这个点，然后再借助 promise 的 then，接下来我们封装一个通用的**执行器函数**：

```js
function Co(iter = {}) {
  // 接受一个迭代器对象, 返回一个promise
  return new Promise((resolve, reject) => {
    function next(data) {
      const { value, done } = iter.next(data);
      if (done) {
        resolve(data);
      } else {
        value
          .then((res) => {
            next(res);
          })
          .catch((err) => {
            reject(err);
          });
      }
    }
    next();
  });
}
```

也就是我们需要递归调用自定义的 next()函数，一直到迭代器自身的 next()方法的 done 属性完成，就注册成功函数，没完成时，报错了，就注册失败函数，真实地使用方法呢就是：

```js
// 1. 借助Promise那一章封装的promisify，返回一个包装fs.readFile后的promise对象
let readFilePromisify = promisify(fs.readFile);

// 2. 书写生成器
function* read() {
  let name = yield readFilePromisify("./name.txt", "utf-8");
  let score = yield readFilePromisify(name, "utf-8");
  let result = yield readFilePromisify(score, "utf-8");
  // 下面这个没啥用，只是为了一会对比async/await的形式
  return result;
}
// 3. 调用前面封装的Co函数，传进一个迭代器参数
const coResult = Co(read());
coResult
  .then((res) => {
    console.log("coResult res is: ", res); // 打印100
  })
  .catch((err) => {
    console.log("coResult err is: ", err);
  });
```

### `生成器+执行器`

经过上面一系列复杂的操作，我们发现，如果多个异步调用，存在前后依赖关系，用`生成器+执行器`可以比较直观的实现（看起来仿佛挺同步的），而且最重要的是看起来非常像`async/await`，我们对比一下：

```js
// 同样的我们使用async/await改造一个上面的read函数
async function readAsync() {
  let name = await readFilePromisify("./name.txt", "utf-8");
  let score = await readFilePromisify(name, "utf-8");
  let result = await readFilePromisify(score, "utf-8");
  return result; // async 返回一个Promise.resolve包装后的新的Promise
}
readAsync()
  .then((res) => {
    console.log("readAsync res is: ", res); // 100
  })
  .catch((err) => {
    console.log("readAsync err is: ", err);
  });
```

至此，`async/await`的原理我们也就弄清楚了，它就是生成器函数+Co 执行器的语法糖抽象，async 相当于我们的 Co 模块必须返回一个 Promise，内部的 await 相当于 yield 关键字，每次中断函数的执行，再来看一个它俩的对比：

```js
// 生成器写法需配合Co使用
function* read() {
  let name = yield readFilePromisify("./name.txt", "utf-8");
  let score = yield readFilePromisify(name, "utf-8");
  let result = yield readFilePromisify(score, "utf-8");
  // 下面这个没啥用，只是为了一会对比async/await的形式
  return result;
}

// `async/await`写法
async function readAsync() {
  let name = await readFilePromisify("./name.txt", "utf-8");
  let score = await readFilePromisify(name, "utf-8");
  let result = await readFilePromisify(score, "utf-8");
  return result; // async 返回一个Promise.resolve包装后的新的Promise
}
```

## `setTimeout setInterval requestAnimationRequest`

`setTimeout setInterval`这两个是常见的定时器，前者在指定时间之后只执行一次回调，后者在指定时间间隔多次执行回调。
两者都有问题，所以我们需要`requestAnimationRequest`，接受一个回调参数，它天然具有节流的功能，在屏幕刷新帧率内只执行一次传入的回调

## `EventLoop`

事件循环是`JavaScript`异步问题中特别重要的一个概念， js 是单线程的，但是还能跑得起来许多复杂的任务，而且并没有阻塞代码，就是靠的这个概念。
这一节聊的话题都是在渲染进程（也就是浏览器内核）中的，Renderer Process 负责一个 tab 内关于网页呈现的所有事情，页面渲染，脚本执行，事件处理等。
渲染进程是多线程的：

1. GUI 渲染线程，重排（回流 reflow） 重绘
2. js 引擎线程（js 内核），这一节的主要内容
3. 定时器线程
4. 事件触发线程
5. 异步请求线程

## 进程和线程

了解 js 运行机制前，先了解一下进程和线程，二者都是 CPU 工作时间片的一个描述：

1. 进程描述了运行指令及加载和保存上下文所需的时间
2. 线程描述了一段指令所需的时间

### js 单线程

js 运行是在单线程执行的，也就是说 js 引擎运行在主线程上，它的好处是节省了内存，节约上下文切换的时间，也没有 🔐 的问题，当然页面中也存在其它多个线程，例如 UI 线程、网络线程等等，那么在这个主线程上，js 代码是怎么执行呢，一般来说 js 中我们把代码分为两大类，三小类：

1. 同步代码： js 执行栈中
2. 异步代码： 宿主环境发起的宏任务异步代码和 js 引擎发起的微任务异步代码。

### 执行栈

先看一个只有同步任务的过程，看一个动图，方便理解：
![执行栈](/images/js/jsstack.gif)

所谓的执行栈就是存储函数调用关系的一个栈结构，遵循先进后出的原则。

### 宏任务、微任务

当有异步任务时，情况变得稍微有点复杂，但是还是可控的 🤣，首先当前的 js 脚本就是一个大的宏任务，所以并不是说宏任务一定比微任务慢，只是说当前执行的任务(**假定都是异步任务的前提**)中 插入的微任务比插入的宏任务优先级高，js 把异步任务分为了两类：

1. 宿主环境发起的叫宏任务
   | 任务 | 任务类型 | 环境
   | ---- | ---- | ---- |
   | script 脚本 | 宏任务 | 浏览器 |
   | DOM 事件 | 宏任务 | 浏览器 |
   | ajax xhr 等网络请求 | 宏任务 | 浏览器 | 
   | 定时器 | 宏任务 | 浏览器 |
   | I/O 操作 | 宏任务 | 浏览器 |
2. js 引擎本身发起的叫微任务
   | 任务 | 任务类型 | 环境
   | ---- | ---- | ---- |
   | Promise.then/catch 中回调 | 微任务 | js 引擎 |

这也是为什么常说的插入的微任务比插入的宏任务优先级高的原因，通过一幅图更好的理解事件循环：

![宏任务队列](/images/js/eventloop.png)
这幅图的过程就是讲的事件循环：

1. 首先执行代码时往执行栈中压入代码，同步代码开始执行，遇到异步代码就暂时挂起
1. 当同步的执行栈的任务都出栈后，js 引擎回去检查任务队列中的回调函数，如果发现有需要执行的回调，就把他拿到执行栈中继续执行
1. 会先插入微任务队列中的任务，全部微任务完成后，在插入宏任务任务队列中的任务
1. 一直重复这个检查过程，直到所有的任务执行完毕。
   在这里我们终于看到的事件循环的真身了 🤣

### 总结

到底什么事事件循环呢：

1. js 是单线程运行，为防止代码阻塞，把代码（任务）分为：同步和异步
2. 同步代码就交给 js 引擎主线程去执行，异步代码交给宿主环境去运行
3. 同步代码放到执行栈中，异步代码等待时机成熟插入到相关任务队列中去排队
4. 执行栈中的代码执行完毕后，会去任务队列中查看是否有异步任务存在，有就送到执行栈中去执行，反复循环查看并执行，这个过程就叫做 `eventLoop`
