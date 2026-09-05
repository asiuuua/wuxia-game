# tests/doubles/ — 确定性 Test Double 专区（04 图 Q-3 / T-R04）

本目录是测试替身（Test Double）唯一合法驻地：
- `fake_*` / `stub_*` / `mock_*` 前缀 .gd 文件只准出现在本目录（GATE41 module_scope 机器校验）；
- 生产代码（core/data/services/scenes/autoload）禁引用 tests/ 任何内容（GATE41 T-R05）；
- 替身必须确定性：禁真实磁盘/真实时钟/全局随机（宪法 §82 / T-R03）；
- 时间替身优先复用 core/kernel 的 FakeClock/ReplayClock（02 图基建，他窗施工中）。
