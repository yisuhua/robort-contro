# 本地固定交付区（工业机器人）

这个文件夹是本项目固定的 **ChatGPT 交付入口**。每次在 Windows 运行
`integration/scripts/run-desktop-tests.ps1` 后，脚本会**自动生成或更新**：

- `LATEST.md`：最新运行状态、各项 PASS / FAILED / BLOCKED / SKIPPED、失败摘要；
- `LATEST.json`：结构化状态、Git SHA、每项日志相对路径；
- `history/<run_id>.md/json`：历史运行快照（只增不覆盖，不删除失败记录）；
- `exports/LATEST.zip`：可以**手动上传到当前 ChatGPT 对话**的精简交付包；
- `exports/run_<run_id>.zip`：对应每次独立运行的交付版本；
- `inbox/`：用户自己存放截图、Excel/CSV、额外实验数据、说明等。

所有自动生成的交付产物和 `inbox` 内容都被 `.gitignore` 排除，
**不会因为执行 `git pull`、`git status` 自动上传到 GitHub**。
脚本不会发网络请求、不会自动向 ChatGPT 提交资料，也不包含全部原始日志。
`integration/test-results/<run_id>/` 保留完整日志；用户可以核查敏感信息后再
挑选文件单独上传。预设敏感字段替换并不能保证内容完全脱敏。

固定交付流程：

1. 在 Windows 桌面运行一键测试脚本。
2. 打开 `桌面/robort-contro/handoff/exports/LATEST.zip`。
3. 把 ZIP 作为聊天附件上传到 ChatGPT；如需要额外补充，用 `inbox/` 存放，
   再选择性上传。
4. ChatGPT 以 ZIP 内最新 SHA 与测试时间为核验依据，不把上次数据当作最新。

**重要**：每次测试仅自动刷新交付文件，不会自动分析实验结果生成研究结论，
不会执行未授权的重复实验，不会合并 main 或重写以前的 Latest Valid。
