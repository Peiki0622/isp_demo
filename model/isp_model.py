"""Top-level software golden model for the reconstructed ISP pipeline."""

from model.blc import apply_blc
from model.awb_gain import apply_awb_gain


def run_pipeline(raw, cfg):
    """执行当前已实现的 BLC；cfg 使用现有配置文件对应的普通字典。

    pipeline.blc 缺省关闭；启用时 blc.offset 缺省为零。配置文件读取
    由调用者负责，本阶段不引入 YAML 依赖或未实现的后续算法。
    """
    # 算法按硬件顺序串接，不能在 BLC 后提前返回而跳过后续 AWB。
    pipeline = cfg.get("pipeline", {})
    result = raw
    if pipeline.get("blc", False):
        result = apply_blc(result, cfg.get("blc", {}).get("offset", 0))
    if pipeline.get("awb_gain", False):
        gains = cfg.get("awb_gain", {})
        result = apply_awb_gain(result, gains.get("r", 4096),
                                gains.get("g", 4096), gains.get("b", 4096))
    return result
