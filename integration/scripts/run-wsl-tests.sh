#!/usr/bin/env bash
# WSL isolated ROS2/Gazebo CI demo. No software installation; no physical robot interfaces.
# Args: Windows-mounted Git repo, Windows-mounted reports path.
set -uo pipefail
REPO="${1:?expected WSL path to repository}"
OUT="${2:?expected WSL output path}"
mkdir -p "$OUT"
: > "$OUT/status.tsv"
has_fail=0
has_block=0
record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$OUT/status.tsv"
  printf '[%s] %s: %s\n' "$2" "$1" "$3"
  if [[ "$2" == FAILED ]]; then has_fail=1; fi
  if [[ "$2" == BLOCKED ]]; then has_block=1; fi
}
check() {
  local name="$1"; shift
  if "$@" > "$OUT/${name}.log" 2>&1; then
    record "$name" PASS "$OUT/${name}.log"
    return 0
  else
    record "$name" FAILED "$OUT/${name}.log"
    return 1
  fi
}
if command -v python3 >/dev/null 2>&1; then
  check 'offline-python' python3 -m unittest discover -s "$REPO/integration/tests" -p 'test_*.py' -v || true
else
  record 'offline-python' BLOCKED 'WSL Python 3 unavailable'
fi
check 'bash-syntax' bash -n "$REPO/integration/scripts/run-wsl-tests.sh" "$REPO/integration/scripts/p0_inventory.sh" "$REPO/integration/scripts/verify_ros_demo.sh" || true
if [[ -z "${ROS_DISTRO:-}" ]]; then
  shopt -s nullglob
  rosdirs=(/opt/ros/*)
  if (( ${#rosdirs[@]} == 1 )); then
    ROS_DISTRO="${rosdirs[0]##*/}"
  else
    record 'ros2-distro' BLOCKED 'ROS_DISTRO unset and zero or multiple /opt/ros distros'
    exit 2
  fi
fi
if [[ ! -f "/opt/ros/$ROS_DISTRO/setup.bash" ]]; then
  record 'ros2-distro' BLOCKED "Not installed: /opt/ros/$ROS_DISTRO/setup.bash"
  exit 2
fi
# ROS setup scripts may use optional unset variables; do NOT set -u while sourcing.
# shellcheck disable=SC1090
set +u
source "/opt/ros/$ROS_DISTRO/setup.bash"
set -u
check 'inventory' bash "$REPO/integration/scripts/p0_inventory.sh" "$OUT/inventory.txt" || true
needed=(ros_gz_sim ros_gz_bridge gz_ros2_control robot_state_publisher controller_manager
        joint_trajectory_controller joint_state_broadcaster xacro)
missing=()
for pkg in "${needed[@]}"; do
  if ! ros2 pkg prefix "$pkg" >/dev/null 2>&1; then missing+=("$pkg"); fi
done
for cmd in colcon gz timeout; do
  if ! command -v "$cmd" >/dev/null 2>&1; then missing+=("$cmd"); fi
done
if (( ${#missing[@]} > 0 )); then
  record 'runtime-prerequisites' BLOCKED "Missing: ${missing[*]}; no auto-install"
  exit 2
fi
record 'runtime-prerequisites' PASS "ROS_DISTRO=$ROS_DISTRO; modern Gazebo components present"
# Build within Linux filesystem, NOT inside the mounted Windows Desktop.
TMPROOT="$(mktemp -d -t robort-integration-XXXXXXXX)"
mkdir -p "$TMPROOT/ws/src"
cp -a "$REPO/integration/ros2_ws/src/industrial_robot_integration" "$TMPROOT/ws/src/"
if ! check 'ros2-colcon-build' bash -c 'colcon --log-base "$1/log" build --base-paths "$1/ws/src" --build-base "$1/build" --install-base "$1/install"' _ "$TMPROOT"; then
  exit 1
fi
source "$TMPROOT/install/setup.bash"
xacroFile="$TMPROOT/ws/src/industrial_robot_integration/urdf/robot.urdf.xacro"
controllerConfig="$TMPROOT/install/industrial_robot_integration/share/industrial_robot_integration/config/controllers.yaml"
if ! check 'xacro-kinematic' bash -c 'xacro "$1" demo_mode:=false > "$2"' _ "$xacroFile" "$OUT/kinematic.urdf"; then exit 1; fi
if ! check 'xacro-demo' bash -c 'xacro "$1" demo_mode:=true controller_yaml:="$3" > "$2"' _ "$xacroFile" "$OUT/demo.urdf" "$controllerConfig"; then exit 1; fi
check 'expanded-urdf-kinematic' python3 "$REPO/integration/tests/validate_expanded_urdf.py" "$OUT/kinematic.urdf" kinematic || true
check 'expanded-urdf-demo' python3 "$REPO/integration/tests/validate_expanded_urdf.py" "$OUT/demo.urdf" demo || true
if ! check 'gz-urdf-to-sdf' bash -c 'gz sdf -p "$1" > "$2"' _ "$OUT/demo.urdf" "$OUT/demo.sdf"; then exit 1; fi
# Dedicated ROS domain; this script is DEMO only and never connects hardware.
export ROS_DOMAIN_ID=143
export ROS_LOCALHOST_ONLY=1
export GZ_PARTITION="robort_desktop_demo_${USER:-user}_$$"
ros2 launch industrial_robot_integration demo.launch.py > "$OUT/gazebo-launch.log" 2>&1 &
launchPid=$!
cleanup() {
  kill "$launchPid" 2>/dev/null || true
  wait "$launchPid" 2>/dev/null || true
}
trap cleanup EXIT
ready=0
for _ in $(seq 1 75); do
  if ! kill -0 "$launchPid" 2>/dev/null; then break; fi
  controllers="$(timeout 4 ros2 control list_controllers 2>/dev/null || true)"
  if grep -Eq 'joint_state_broadcaster[[:space:]]+joint_state_broadcaster/JointStateBroadcaster[[:space:]]+active' <<< "$controllers" &&
     grep -Eq 'joint_trajectory_controller[[:space:]]+joint_trajectory_controller/JointTrajectoryController[[:space:]]+active' <<< "$controllers"; then
     ready=1; break
  fi
  sleep 2
done
if (( ready != 1 )); then
  record 'gazebo-controllers' FAILED "No two active demo controllers; check $OUT/gazebo-launch.log"
  exit 1
fi
record 'gazebo-controllers' PASS 'Both demo controllers active'
check 'ros2-state-feedback' timeout 40 ros2 run industrial_robot_integration feedback_probe --samples 10 --timeout 30 || true
check 'ros2-motion-roundtrip' timeout 50 ros2 run industrial_robot_integration command_probe || true
if (( has_fail != 0 )); then exit 1; fi
if (( has_block != 0 )); then exit 2; fi
exit 0
