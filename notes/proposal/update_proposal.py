"""Update the retained one-page proposal without rebuilding its OOXML package."""
from pathlib import Path
from zipfile import ZipFile
from hashlib import sha256
from lxml import etree
import json

ROOT = Path(r'D:/Study_Works/MoonBit/参赛要求（先看）')
REFERENCE = ROOT / 'MoonPortCheck项目申报书_v0.3.docx'
OUTPUT = ROOT / 'MoonPortCheck项目申报书_v0.3_验收补强.docx'
WORK = Path(__file__).parent
NS = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
W = '{' + NS['w'] + '}'
R = '{' + NS['r'] + '}'

replacements = {
    11: '以文件交换为例：a=X、b=Y 交换后路径集合不变，但来源必须变为 a=Y、b=X。MoonPortCheck v0.3 将交付意图编译为满足前置条件的中转与移动步骤，再由独立审计器重放，识别路径合法却来源错误的计划。MoonBit 实现身份、依赖和状态迁移；Node.js 适配快照与 CLI。产品仅生成和审计计划。',
    12: '复用基础与独立新增：沿用 v0.2 的路径检查、glob、索引和静态比较；本期新增初态来源身份、操作依赖与环中转、外部计划独立审计，覆盖从意图到逐步执行正确性的完整语义。',
    14: '1. 初态身份：以命名空间和初始路径区分来源，多根同名文件及 Linux 来源 A/a 不混淆。',
    15: '2. 交付映射：文件 Copy/Move、目录前缀 Copy 按初态展开，保留空目录及只读来源。',
    16: '3. 操作约束：每步核对来源身份、目标占用与父目录类型，禁止覆盖或改变无关条目。',
    17: '4. 依赖与中转：处理交换环、文件腾空后建目录及大小写改名，避让初态和最终目标。',
    18: '5. 独立审计：自行推导预期终态，拒绝错身份、错顺序、遗漏操作和临时文件残留。',
    19: '6. 库与 CLI：plan / audit-plan 输出 JSON、文本、Markdown；接受其他合法操作顺序。',
    21: '验收证据：独立参考模型对 838 组请求判定可行性，并直接重放 496 个可行计划的实际步骤；隔离目录核对文件字节、无关条目与临时清空。固定 v0.2 源码及 CLI 发行包的实际交付可复现。新增公共 API 经外部 MoonBit 模块在 JS/wasm-gc 消费，保留旧接口回归和万条映射规模验证。提供正确与错误计划、运行脚本及逐步说明。',
}

with ZipFile(REFERENCE) as z:
    original = {name: z.read(name) for name in z.namelist()}
doc = etree.fromstring(original['word/document.xml'])
paras = doc.xpath('/w:document/w:body/w:p', namespaces=NS)

def set_text(p, text):
    texts = p.xpath('.//w:t', namespaces=NS)
    if not texts:
        raise ValueError('Expected a supported plain text paragraph')
    texts[0].text = text
    for t in texts[1:]:
        t.text = ''

for index, text in replacements.items():
    set_text(paras[index], text)

# Preserve the title's source appearance, with the required semantic Title style.
ppr = paras[0].find(W + 'pPr')
if ppr is None:
    ppr = etree.Element(W + 'pPr')
    paras[0].insert(0, ppr)
style = ppr.find(W + 'pStyle')
if style is None:
    style = etree.Element(W + 'pStyle')
    ppr.insert(0, style)
style.set(W + 'val', 'Title')

# The existing release and registry hyperlinks become release-status and evidence links.
release = paras[22]
runs = release.xpath('./w:r', namespaces=NS)
runs[0].find(W + 't').text = '交付入口：'
runs[1].find(W + 't').text = '　　复现依据：'
hyperlinks = release.xpath('./w:hyperlink', namespaces=NS)
set_text(hyperlinks[0], 'v0.3 发行与状态')
set_text(hyperlinks[1], '案例与验证说明')
rels = etree.fromstring(original['word/_rels/document.xml.rels'])
targets = {
    hyperlinks[0].get(R + 'id'): 'https://github.com/AlexenderSokolov/moonportcheck/releases/tag/v0.3.0',
    hyperlinks[1].get(R + 'id'): 'https://github.com/AlexenderSokolov/moonportcheck/blob/main/docs/V03_PROGRESS.md',
}
for rel in rels:
    if rel.get('Id') in targets:
        rel.set('Target', targets[rel.get('Id')])

updated = dict(original)
updated['word/document.xml'] = etree.tostring(doc, xml_declaration=True, encoding='UTF-8', standalone=True)
updated['word/_rels/document.xml.rels'] = etree.tostring(rels, xml_declaration=True, encoding='UTF-8', standalone=True)
with ZipFile(REFERENCE) as src, ZipFile(OUTPUT, 'w') as dst:
    for entry in src.infolist():
        dst.writestr(entry, updated[entry.filename])

changed = [name for name in original if original[name] != updated[name]]
assert set(changed) == {'word/document.xml', 'word/_rels/document.xml.rels'}, changed
reference_hash = sha256(REFERENCE.read_bytes()).hexdigest()
inventory = {name: {'size': len(data), 'sha256': sha256(data).hexdigest()} for name, data in original.items()}
(WORK / 'reference-package-inventory.json').write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding='utf-8')
(WORK / 'artifact.md').write_text(f'''# Proposal template contract

Reference: `{REFERENCE}`
SHA256: `{reference_hash}`
Reference render: local `artifacts/proposal-template-reference/reference.pdf` and `page-1.png`; one page verified. Generated renders are kept outside the published source inventory.

Letter portrait 12240 × 15840 twips; margins top 482, bottom 425, left/right 510; one section, one column. No tables, images, field instructions or page furniture.
Source title: centered 18 pt bold Microsoft YaHei; body 11 pt Microsoft YaHei; section headings 12 pt bold except Basic Information 14 pt. Preserve paragraph properties and spacing, section geometry, run properties, styles and all package parts.

Editable slots: body paragraphs 11,12 for introduction and new semantic scope; 14–19 for six capability records; 21 for actual evidence; 22 hyperlink labels and targets for release state and verification. Paragraph 0 receives semantic Title style with its original direct appearance. All other content is preserved. Document relationships only change the two paragraph-22 URL targets. Inventory is `reference-package-inventory.json`.

Acceptance: retained reference hash unchanged; only document.xml and its relationships changed; rendered output remains one page with no clipping; title and body keep source typography. Release-status wording does not assert CI or registry publication.
''', encoding='utf-8')
print(json.dumps({'output': str(OUTPUT), 'reference_sha256': reference_hash, 'changed_parts': changed}, ensure_ascii=False))
