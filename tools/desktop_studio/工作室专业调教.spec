# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['studio_server.py'],
    pathex=[],
    binaries=[],
    datas=[('index.html', '.'), ('startup_card.json', '.'), ('projects', 'projects')],
    # tscn_assets 在 studio_core 的 try 块内导入，静态分析可能漏掉，显式声明。
    # 缺失会导致打包后的 exe 打开「UI 贴图」标签页报「贴图库加载失败」。
    # yaml：project_loader 在工程适配器(Phase 2)中按需 import yaml 读 manifest；
    #   静态分析漏掉，必须显式声明，否则 exe 运行连接器端点时报 ModuleNotFoundError。
    hiddenimports=['tscn_assets', 'yaml'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='工作室专业调教',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
