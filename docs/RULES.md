# portable-windows-v1 规则说明

这是面向一般 Windows 文件交付的固定检查配置，不模拟某一台电脑的全部文件系统行为。名称规则参考 [Microsoft：Naming Files, Paths, and Namespaces](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)；清单格式、诊断编号及分组方式由 MoonPortCheck 定义。

## 清单约定

输入是 UTF-8 JSON 数组，每项具有字符串 `path` 和 `kind`。`kind` 取 `file` 或 `directory`。路径相对于交付根目录，以 `/` 分隔，目录不附加尾部 `/`。中文、名称中间的空格及点开头名称可以正常使用。

```json
[
  { "path": "README.md", "kind": "file" },
  { "path": "results", "kind": "directory" },
  { "path": "results/实验记录.csv", "kind": "file" }
]
```

JSON 或字段类型错误属于输入错误；合法条目中的坏路径属于检查发现。例如 `{"path":"../a","kind":"file"}` 的结构合法，会得到路径诊断。清单中的反斜杠作为非法名称字符报告，不会自动转成分隔符。

## 稳定规则编号

| 编号 | 检查内容 | 例子 |
| --- | --- | --- |
| `PATH_EMPTY` | 空路径 | `""` |
| `PATH_ABSOLUTE` | 以斜杠或反斜杠开头的根路径、UNC 路径 | `/tmp/a`、`\\server\share` |
| `PATH_DRIVE` | 以 ASCII 盘符和冒号开头 | `C:/a`、`C:a` |
| `PATH_EMPTY_COMPONENT` | `/` 分隔产生空路径段 | `a//b`、`a/` |
| `PATH_DOT_COMPONENT` | 单独的 `.` 或 `..` 路径段 | `a/../b` |
| `NAME_INVALID_CHAR` | 名称中含 Windows 保留字符或 U+0000–U+001F 控制字符 | `a:b`、`a\\b`、`bad?.txt` |
| `NAME_RESERVED` | 大小写不敏感的设备保留名，包括首个点后带扩展名的形式 | `CON.txt`、`nul.tar.gz`、`COM¹` |
| `NAME_TRAILING_DOT_SPACE` | 任一路径段以点或空格结尾 | `notes/report.md.`、`data /a` |
| `PATH_DUPLICATE` | 完整路径字符串重复，不丢弃次数 | 同一个 `a.txt` 出现三次 |
| `PATH_CASE_COLLISION` | 路径逐段按 ASCII 大小写折叠后碰撞 | `Data/a` 与 `data/b` 的中间目录 |
| `PATH_KIND_CONFLICT` | 同一折叠路径既作为文件又作为目录 | 文件 `out` 与文件 `out/a.txt` |

设备名集合包括 `CON`、`PRN`、`AUX`、`NUL`、`COM1`–`COM9`、`LPT1`–`LPT9` 以及 `COM`/`LPT` 后接上标 `¹`、`²`、`³`。保留字符为 `< > : " \ | ? *`；`/` 在本工具中作为路径段分隔符处理。

## 集合语义与确定性

`Data/a.csv` 隐含目录 `Data`，因此即使清单没有显式目录项，也会与 `data/b.csv` 冲突。显式目录与它自身的隐含目录兼容，不算重复；重复完整输入条目仍按原次数报告。文件与目录冲突包括大小写折叠后的冲突。

冲突按路径组报告，不展开为所有两两组合。`paths` 在每组内去重，按 UTF-16 码元字典序排列；诊断按规则编号与路径排序，输入重排不改变报告，无时间戳。

`occurrences` 的含义取决于诊断：单条名称／结构问题和 `PATH_DUPLICATE` 使用该完整路径在输入中的出现次数；大小写及文件／目录冲突使用参与冲突的不同前缀拼写数，隐含目录不重复计数。因此 `artifact` 文件与 `artifact/report.txt` 的类型冲突包含一个前缀 `artifact`，其 `occurrences` 为 `1`；这不表示只有一个输入条目。重复次数由独立的 `PATH_DUPLICATE` 诊断保留。扫描问题每项计为 `1`。

结构无效的路径仍接受单条规则检查，完整字符串重复仍可报告；这类路径不进入层级索引，以免制造误导性的目录冲突。一条路径可以触发多个规则。

## 目录扫描与退出码

扫描包含隐藏项，只读取名称和类型，不读取文件内容。根目录自身不算条目。符号链接与 junction 不跟随；编码不能无损表示、无法读取或不支持的文件类型都会令 `complete=false`。这时已发现的路径问题仍保留，但退出码为 `3`。

| 退出码 | 含义 |
| --- | --- |
| `0` | 检查完整，已覆盖规则没有发现问题 |
| `1` | 检查完整，存在规则发现 |
| `2` | 参数、UTF-8、JSON、配置或清单结构错误 |
| `3` | I/O 失败或扫描不完整；优先于路径发现的 `1` |

扫描问题使用 `SCAN_IO_ERROR`、`SCAN_LINK_SKIPPED`、`SCAN_TYPE_UNSUPPORTED`、`SCAN_NAME_ENCODING`。输入错误使用 `ARGUMENT_ERROR`、`INPUT_ENCODING`、`INPUT_SCHEMA`、`INPUT_JSON`、`INPUT_IO_ERROR`、`INPUT_CONFIG`、`PATTERN_INVALID`，以错误响应输出，不伪装成成功的空报告。`INPUT_CONFIG` 用于配置文件结构错误（非法 JSON、非对象、错误的 `schema_version`、未知字段）；非法排除模式单独使用 `PATTERN_INVALID`。

## 明确未覆盖

- ASCII 以外的完整 Unicode 大小写等价与 Unicode 规范化。
- 长路径、路径段长度、8.3 别名以及目标文件系统的特殊限制。
- 权限、文件内容、复制过程、链接目标和并发修改后的最终状态。
- Windows 扩展命名空间的所有例外或所有应用程序的兼容性。

`complete=true` 表示本次输入在已覆盖配置内检查完整。清单结果仅描述提供的条目；它不证明真实目录与清单一致。`0` 也不保证文件在任意 Windows 环境均能成功复制或打开。
