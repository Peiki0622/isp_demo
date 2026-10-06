"""Top-level software golden model for the reconstructed ISP pipeline."""

from model.blc import apply_blc
from model.awb_gain import apply_awb_gain
from model.demosaic import apply_demosaic


def run_pipeline(raw, cfg):
    """依次执行已启用的 BLC、AWB Gain、Demosaic；cfg 是普通字典。

    pipeline.blc 缺省关闭；启用时 blc.offset 缺省为零。配置文件读取
    由调用者负责，不引入 YAML 依赖。demosaic 缺省关闭；启用后返回
    (H,W,3) RGB12，否则维持既有 RAW 返回接口。
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
    # 首次从单通道 RAW 转换成三通道 RGB，必须放在 RAW 配置算法之后。
    if pipeline.get("demosaic", False):
        result = apply_demosaic(result)
    return result
