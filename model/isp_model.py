"""Top-level software golden model for the reconstructed ISP pipeline."""

from model.blc import apply_blc


def run_pipeline(raw, cfg):
    """执行当前已实现的 BLC；cfg 使用现有配置文件对应的普通字典。

    pipeline.blc 缺省关闭；启用时 blc.offset 缺省为零。配置文件读取
    由调用者负责，本阶段不引入 YAML 依赖或未实现的后续算法。
    """
    if cfg.get("pipeline", {}).get("blc", False):
        return apply_blc(raw, cfg.get("blc", {}).get("offset", 0))
    return raw
