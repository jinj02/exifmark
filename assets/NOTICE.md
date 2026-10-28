# 相机品牌字标资源

内置15个品牌字标：SONY、Canon、Nikon、FUJIFILM、Leica、Panasonic、LUMIX、PENTAX、RICOH、Hasselblad、SIGMA、DJI、Kodak、OLYMPUS和Phase One。

## 来源

保留下载的SVG源文件，来源如下。SONY下载于2026年10月27日，其余资源下载于2026年10月28日。

| 文件 | 来源 |
| --- | --- |
| `sony.svg` | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Sony_logo.svg) |
| `canon.svg` | [Canon官方字标](https://myid.canon/prd/1.1.38.1/canonid-assets/svg/Canon.svg) |
| `olympus.svg` | [Olympus欧洲官网](https://cdn.aws.olympus.eu/static/img/logo/olympus-logo.svg) |
| `pentax.svg` | [PENTAX官方网站](https://pentax.eu/cdn/shop/files/dark-logo.svg?v=10704441403078636815) |
| `nikon.svg`、`fujifilm.svg`、`leica.svg`、`panasonic.svg`、`dji.svg`、`kodak.svg` | [Simple Icons](https://github.com/simple-icons/simple-icons/tree/develop/icons)，对应同名字标；图标集采用[CC0-1.0](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md) |
| `lumix.svg`、`ricoh.svg`、`sigma.svg`、`hasselblad.svg`、`phaseone.svg` | [Camera-Logos-SVG](https://github.com/HiSeatown/Camera-Logos-SVG/tree/main/Camera-Logos-SVG)，依次来自`Lumix_Black.svg`、`Ricoh_Color.svg`、`SIGMA_Black.svg`、`hasselblad-Black.svg`、`phaseone.svg` |

品牌名称与字标的相关权利归各自权利人所有。字标仅用于标识照片卡片的相机品牌；exifmark与上述厂商及Adobe无隶属、赞助或官方合作关系。品牌资源的使用权与插件源码分开处理，来源图标集的许可不授予商标权。

## 重新生成

运行`python3 scripts/prepare-logo.py`生成`renderer/Sources/ExifmarkCore/Resources/<brand>-black.pdf`和`<brand>-white.pdf`。该开发工具需要`fonttools`；插件构建与运行均无需Python或fonttools。

生成时保留矢量轮廓、应用SVG变换、裁去外部留白，并统一填充为黑色或白色。渲染器同时限制字标宽度和高度以适配横向字标及圆形徽标。
