# Industrial Robot 6R — MATLAB / ROS 2 / Gazebo integration

**Status: PROPOSED implementation; offline contract tests only.**
This directory is a separate, additive integration layer for the existing
industrial-robot Project. It does not modify `matlab/robot_model/build_robot.m`
or its Stage-2 user-reported kinetic checks. It is **not** a validated robot,
a CAD collision model, a real actuator model, or an approved safe controller.

## Baseline, source, and exact scope

- MATLAB geometry source: `matlab/robot_model/build_robot.m` in this repository.
- 6R axis order in local joint frames: Z, Y, Y, X, Y, X (Stage-1 WORKING).
- d1=0.320, a1=0.080, L2=0.350, L3=0.340, L4=0.130 m.
- MATLAB `robot.DataFormat=column`, bodies `link1`..`link6`, `tool_flange`.
- Stage-1 zero position [0.900, 0, 0.320] m.
- J1 mechanical limit ±170 degrees; **J2–J6 actual physical limits unknown**.
- Existing MATLAB joint axes are not yet cross-validated against full CAD.

The Xacro is a **derived PROPOSED adapter**, kept in sync with the MATLAB
source by CI tests. It is not a second authority for actual geometry.
Changes to either model require explicit review and cross-tool verification.

## Project layout

- `ros2_ws/src/industrial_robot_integration/urdf/robot.urdf.xacro` — same six
  joint transforms with an explicit demo-only mode for Gazebo dynamics.
- `ros2_ws/src/industrial_robot_integration/config/controllers.yaml` — one
  joint-state broadcaster and one position trajectory controller.
- `ros2_ws/src/industrial_robot_integration/worlds/empty.sdf` — minimal GZ world.
- `ros2_ws/src/industrial_robot_integration/launch/demo.launch.py` — GZ server,
  ROS clock bridge, RSP, spawn, ordered controller spawners.
- `ros2_ws/src/industrial_robot_integration/industrial_robot_integration/feedback_probe.py`
  — read-only joint-state probe with name/time/NaN checks.
- `matlab/ros2_roundtrip_demo.m` — small demo J1 command with validated feedback.
- `python_adapter/` — **schema only** for future disassembly integration.
- `tests/` — offline static checks and independent math samples.
- `docs/INTERFACES.md` — topic ownership and operational failure paths.
- `docs/CHECKPOINT.md` — preserved state and test evidence.

## P0 — inventory before running any demo

ROS 2 and GZ versions are **not confirmed** on the target system. Choose an
OS/ROS/Gazebo combination with available compatible `gz_ros2_control`,
`ros_gz_sim`, `ros_gz_bridge`, and controllers. This code targets **modern
Gazebo Sim** (`gz sim`), NOT Gazebo Classic (`gazebo`) or an arbitrary
`ign gazebo` compatibility alias. Do not auto-upgrade an existing environment.

On a provisioned **Linux ROS 2/GZ host**, from the repository root:

```bash
bash integration/scripts/p0_inventory.sh ./reports/p0_inventory.txt
python3 -m unittest discover -s integration/tests -v
```

The first command is read-only, and does not install anything. It records
available binaries/packages; its output is not proof of compatibility.
Offline static checks require Python 3.8+ only.

## P1 — build / observe kinematic model

**Only after versions and dependencies have been confirmed on the target host:**

```bash
source /opt/ros/$ROS_DISTRO/setup.bash
cd integration/ros2_ws
colcon build --symlink-install --packages-select industrial_robot_integration
source install/setup.bash
ros2 run xacro xacro \
  src/industrial_robot_integration/urdf/robot.urdf.xacro \
  demo_mode:=false > /tmp/industrial_robot_kinematic.urdf
```

The `demo_mode:=false` expansion is a **kinematic/visual description**. It
deliberately contains no official CAD collision meshes or verified inertias.
Running the Xacro expansion successfully does not establish Gazebo dynamics
or CAD equivalence. Check all six joint origins, axes, fixed flange and
quaternions against MATLAB over multiple configurations before claiming P1
VALID.

## P2 — launch simulation DEMO (no physical hardware)

The following **is a future instruction**, not a command that has been run:

```bash
source /opt/ros/$ROS_DISTRO/setup.bash
cd integration/ros2_ws
source install/setup.bash
ros2 launch industrial_robot_integration demo.launch.py
```

The launch uses `demo_mode:=true` and **fabricated demonstrator-only inertias,
primitive boxes, 50 N m-equivalent effort fields, and 1 rad/s velocity fields**.
These numbers are software placeholders to exercise middleware, NOT Project
actuator or performance decisions; they must never inform procurement or CAE.
J2–J6 are represented as continuous **only to avoid asserting unconfirmed
mechanical limits**. The visual and collision primitives are not valid for
self-collision/obstacle conclusions. Do not attach a real robot.

Once started, from a separately sourced ROS terminal:

```bash
ros2 control list_controllers
ros2 topic type /clock
ros2 topic type /joint_states
ros2 topic echo /joint_states --once
ros2 run industrial_robot_integration feedback_probe --samples 10 --timeout 25
bash integration/scripts/verify_ros_demo.sh ./reports
```

Both controllers must report `active`. Observe whether GZ plugin actually
registered controllers; if not, stop and inspect compatibility, plugin loading,
`robot_description` and controller-manager logs. Do **not** bypass failures.

## P3 — MATLAB ROS Toolbox demonstration

On a **separate supported MATLAB environment** with ROS Toolbox, Robotics
System Toolbox, compatible DDS discovery/network, and the demo already running:

```matlab
repoRoot = "C:\path\to\robort-contro";
addpath(fullfile(repoRoot,"integration","matlab"));
result = ros2_roundtrip_demo(repoRoot);
```

The script re-uses `build_robot.m` and sends only a 0.03 rad J1 motion when
it sees near-home six-joint feedback. Its 0.01 rad error check is a PROPOSED
diagnostic threshold, not an official robot accuracy criterion. No real robot
or high-speed trajectory is authorized by this example. The result captures
feedback and MATLAB-predicted TCP coordinates; it **does not** independently
compare a Gazebo TF TCP or validate tracking over a continuous trajectory.

## P4 — final acceptance gate (still NOT RUN)

Require captured evidence on the actual target system:

1. exact ROS distro, Gazebo release, installed package versions, GIT SHA;
2. generated URDF/Xacro logs, independently compared FK of MATLAB vs URDF;
3. node graph, unique clock publisher, active controller state, stable `/clock`;
4. `/joint_states` six unique names in radians, monotonic simulation timestamps;
5. a commanded small trajectory, changed feedback, controller state, and
   independent pose checks with preapproved numerical thresholds;
6. explicit failure cases (controller missing, wrong names/order, disconnection,
   simulation clock resets) with retained logs and safe stop behavior;
7. documented distinction between demo dynamics and genuine CAD/CAE model.

**Passing offline CI only allows "static PASS".** Runtime ROS/Gazebo, MATLAB
R2024b, CAD collisions, dynamics, safety and controller performance stay
**NOT RUN** until corresponding real execution and artifacts exist.

## Reference documentation

- Gazebo ROS 2 Sim: https://github.com/gazebosim/ros_gz
- Gazebo ros2_control plugin: https://control.ros.org/jazzy/doc/gz_ros2_control/doc/index.html
- Joint trajectory controller: https://control.ros.org/humble/doc/ros2_controllers/joint_trajectory_controller/doc/userdoc.html
- MATLAB ROS Toolbox: https://www.mathworks.com/help/ros/
