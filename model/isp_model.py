"""Top-level software golden model for the reconstructed ISP pipeline."""

from model.blc import apply_blc
from model.awb_gain import apply_awb_gain
from model.demosaic import apply_demosaic
from model.ccm import apply_ccm, IDENTITY_MATRIX


def run_pipeline(raw, cfg):
    """依次执行已启用的 BLC、AWB Gain、Demosaic、CCM；cfg 是普通字典。

    pipeline.blc 缺省关闭；启用时 blc.offset 缺省为零。配置文件读取
    由调用者负责，不引入 YAML 依赖。demosaic 缺省关闭；启用后返回
    (H,W,3) RGB12，否则维持既有 RAW 返回接口。CCM 缺省关闭；启用时
    未给 matrix 使用整数 identity。CCM 要求三通道输入，RAW 二维输入
    未经 Demosaic 而直接启用 CCM 会明确报错，不静默复制通道。
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
    # CCM 必须在完成 RAW->RGB 之后执行；缺省关闭保留历史 RAW 调用行为。
    if pipeline.get("ccm", False):
        result = apply_ccm(result, cfg.get("ccm", {}).get("matrix", IDENTITY_MATRIX))
    return result
