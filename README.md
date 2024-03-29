### simple-markdown-parse
---
### Markdown Grammar
- headline
  ```
    # heading1 => <h1></h1>
    ## heading2 => <h2></h2>
    ### heading3 => <h3></h3>
    #### heading4 => <h4></h4>
    ##### heading5 => <h5></h5>
    ###### heading6 => <h6></h6>
  ```
- paragraph
  ```
    hello world
    <p>hello world</p>
  ```
- strong
  ```
    **test** => <strong>test</strong>
    *test* => <em>test</em>
    ***test*** => <strong><em>test</em></strong>
    __hello__ => <strong>test</strong>
  ```
- blockquote
  ```
    > hello => <blockquote>hello</blockquote>

    > hello
    >
    >> world 
    => <blockquote>hello<blockquote>world</blockquote></blockquote> 
  ```
- separation line
  ```
    --- => <hr>
  ```
- link
  ```
    [link](https://github.com/) => <a href="https://github.com/">link</a>
    <https://github.com> => <a href="https://github.com/">https://github.com</a>
  ```
- image
  ```
    ![img](/assets/img/philly-magic-garden.jpg)
    => <img src="/assets/img/philly-magic-garden.jpg" alt="img">

    [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
    => <a href="https://github.com/Chanyon"><img src="/assets/img/ship.jpg" alt="image"></a>"
  ```
- delete line
  ```
    ~~test~~ => <p><s>test</s></p>
    hello~~test~~world => <p>hello<s>test</s>world</p>
  ```
- code
  ```
  `test` => <code>test</code>
  `` `test` `` => <code> `test` </code>
  =```
    {
     "width": "100px",
     "height": "100px",
    "fontSize": "16px",
    "color": "#ccc",
    }
   =```
   => <pre><code><br>{<br>  "width": "100px",<br>  "height": "100px",<br>  "fontSize": "16px",<br>  "color": "#ccc",<br>}<br></code></pre>
  ```

- footnote
  ```
  test[^1]
  [^1]: ooooo
  =>  <p>test<a id="src-1" href="#target-1">[1]</a></p>
  <section>
  <p><a id="target-1" href="#src-1">[^1]</a>:  ooo</p>
  </section>
  ```
- task list
  ```
  - [ ] task one
  - [x] task two
  ```
- table
  ```
  | Syntax      | Description | Test |
  | :---------- | ----------: | :-----: |
  | Header      | Title       |  will |
  | Paragraph   | Text        |  why  |
  ```

- unordered list
  ```
  - test
    - test2
        - test3
    - test4
  - test5
  - test6
  ```
- ordered list
  ```
  1. test
    1. test2
        1. test3
    2. test4
  2. test5
  3. test6
  ```
- escape characters
  ```
   \[\]
   \<test\>
   \*test\* \! \# \~ \-
   \_ test \_ \(\)
  ```

### DONE
- [x] 无序列表
- [x] 有序列表
- [x] 表格语法
- [x] 内嵌HTML
- [x] 脚注(footnote)
- [x] task list 
- [x] 转义字符
- [x] html tag inline style
- [X] 代码块高亮 \```c ```
- [x] 标题目录