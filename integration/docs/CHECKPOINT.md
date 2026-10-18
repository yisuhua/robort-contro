# Integration working-state checkpoint

Captured intent: add ROS 2 + Gazebo + MATLAB communication architecture to
the industrial robot Project in GitHub, WITHOUT executing anything on the
user's Windows/MATLAB/ROS2/Gazebo installation.

## Protected baseline

- Repository: `yisuhua/robort-contro`.
- Starting default-branch HEAD (read): `bd70a9a91a8b410aa19db866caeeedbf2598ae8c`.
- Preserve `matlab/robot_model/build_robot.m`, Stage 2 scripts and results.
- No new CAD geometry, dynamics, limits, algorithm decisions or real
  verification data should replace existing valid information.
- Frame transformations follow known Stage-1 mathematical working baseline.
- New URDF, demo dynamics, ROS interfaces, MATLAB ROS bridge are PROPOSED.

## Test matrix

| Test | Status | Evidence requirements |
|---|---|---|
| GitHub writes, commit, branch and readback | Pending until actions return | refs, tree, file list |
| Python offline geometry and schema checks | NOT RUN before CI | Python test output |
| Bash and Python syntax | NOT RUN before CI | bash -n / py_compile |
| ROS 2 package colcon build | NOT RUN | actual colcon build log |
| Xacro expansion with ROS 2 | NOT RUN | resulting URDF, tool versions |
| Gazebo plugin/controller launch | NOT RUN | launch logs, active controllers |
| MATLAB R2024b ROS Toolbox roundtrip | NOT RUN | versioned console/figures |
| CAD interference / 35-point scan | NOT RUN | genuine CAD inspection |
| IK/workspace limitations | Open | separate current Project tests |
| Dynamics, FEA, physical control | NOT RUN | appropriate target execution |

## Retry and recovery

If any GitHub transaction fails, keep the last confirmed branch ref and
creation SHA. Retry by reading current branch tree first; never force-update
`main`. If offline tests fail, modify only affected new files in the feature
branch and rerun focused tests, then confirm unaffected kinematic regression.
Keep the user-reported MATLAB Stage 2 result separate from newly computed
static checks and do not relabel it as new MATLAB verification.
