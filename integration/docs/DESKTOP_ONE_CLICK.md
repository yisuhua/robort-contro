# 一键部署到 Windows 桌面并执行全套可用测试

**操作权限**：此工程不远程连接用户电脑。只有用户在 Windows PowerShell
手动运行下面的命令时，才会创建目录、执行本地测试和启动隔离的 WSL/Gazebo demo。
不自动安装软件、不变更现有主项目基线、不连接实体机械臂。

## 第一回：复制整段到 Windows PowerShell

```powershell
$desktop = [Environment]::GetFolderPath('Desktop')
$repo = Join-Path $desktop 'robort-contro'
git clone --branch feature/matlab-ros2-gazebo-integration --single-branch https://github.com/yisuhua/robort-contro.git $repo
if ($LASTEXITCODE -ne 0) { throw 'Clone failed; automatic tests cancelled.' }
& (Join-Path $repo 'integration/scripts/run-desktop-tests.ps1') -RepoRoot $repo
```

**真实目录**：`[Environment]::GetFolderPath('Desktop')\robort-contro`。
使用 Windows 提供的 Desktop 目录，包括 OneDrive 已重定向的 Desktop；
不猜测 `C:\Users\<username>`。如果目录已存在，禁止直接再次 clone/覆盖。

## 第二回及以后：安全更新 + 自动运行全套测试

```powershell
$repo = Join-Path ([Environment]::GetFolderPath('Desktop')) 'robort-contro'
& (Join-Path $repo 'integration/scripts/bootstrap-desktop.ps1')
```

bootstrap 校验 GitHub origin、工作树无未提交修改，再
`git fetch` → `git checkout feature/...` → `git merge --ff-only`；
发生冲突/有未提交修改则拒绝更新，不执行测试。

## 实际测试顺序和可用性门禁

默认不跳过已安装的可测试模块：

1. Git HEAD/工作区与 Python 单元测试 + Python 语法（Windows）；
2. MATLAB R2024b 存在则独立运行 Stage-1、Stage-2、Stage-3 脚本，
   每个阶段使用独立 `matlab -batch` 会话，错误保留原始输出；
3. WSL 存在则先执行离线测试和依赖核验，不静默安装；具备 ROS 2
   和现代 Gazebo 依赖时在 **WSL Linux 文件系统临时工作空间**编译，
   展开 kinematic/demo Xacro、真实 URDF→SDF，启动 demo、检查两个
   controller active、关节状态和 J1 小角度闭环；
4. MATLAB ↔ ROS 2 网络联调不盲目自动发送命令：
   必须先实际确认 ROS Toolbox、ROS 发行版兼容及跨 WSL DDS 发现，
   目前固定为 `BLOCKED`，不伪造已完成。独立拆解方向生成仅保留接口。
5. CAD/SolidWorks 35 点扫描、动力学真实惯量/力矩、真实机器人安全，
   不属于可自动运行的当前代码；均为 `NOT RUN`。

`-SkipMatlab` 和 `-SkipWSL` 只用于明确自愿的诊断模式；默认运行不跳过。
如果缺少依赖，状态标 `BLOCKED` 而不是 PASS。

## 结果保存到桌面项目内

```text
Desktop/
└── robort-contro/
    ├── .git/
    ├── matlab/
    └── integration/
        ├── scripts/
        │   ├── bootstrap-desktop.ps1
        │   ├── run-desktop-tests.ps1
        │   └── run-wsl-tests.sh
        └── test-results/                 # ignored by Git
            └── yyyyMMdd_HHmmss_fff/
                ├── summary.json
                ├── matlab-stage1-fk.log
                ├── matlab-stage2-joint-motion.log
                ├── matlab-stage3-ik.log
                ├── wsl-ros2-gazebo.log
                └── wsl/
                    ├── status.tsv
                    ├── inventory.txt
                    ├── demo.urdf
                    ├── demo.sdf
                    ├── gazebo-launch.log
                    └── [per-test logs]
```

退出码：`0` 全部适用测试 PASS（不代表全部研究目标已验证）；
`1` 有真实失败；`2` 缺依赖/有明确阻塞项但没有其他失败。

## 使用前

- Windows Git for Windows：`git --version`
- Windows Python：`python --version`（GitHub Actions 静态离线测试也可代替）
- 本机 MATLAB R2024b + Robotics System Toolbox（若希望测试 Stage 1–3）。
- WSL Ubuntu/ROS 2/Gazebo 现代版本和已安装的相关软件包
  （`colcon`、`ros_gz_sim`、`ros_gz_bridge`、`gz_ros2_control`、
  `controller_manager`、`joint_trajectory_controller`、
  `joint_state_broadcaster`、`xacro`）。
- 运行前退出已有的测试演示实例，避免重复实体/控制器。

Windows 的 Desktop 文件夹只保存 **Git 仓库和最终日志**，
WSL `colcon` 中间文件在 Linux 临时目录运行，不把 WSL 的构建产物放在
NTFS Desktop 上以避免跨系统符号链接/权限问题。

## 风险与已知失败

截至该功能提交前，GitHub hosted ROS 2 Jazzy 确认成功安装、编译并激活
两个 controller，但 Gazebo 整个云端关节反馈测试 **FAILED**；
用户本机 MATLAB/WSL 尚无真实记录。新增脚本只自动重现并记录问题，
**不会**通过删校验、放宽阈值、隐藏失败或替换既有 MATLAB 源代码来获得 PASS。

**不要**将 `integration/ros2_ws` 与真实硬件 ROS_DOMAIN_ID 共享。
WSL demo 默认隔离至 ROS_DOMAIN_ID=143，消息在本机 localhost 范围内。
