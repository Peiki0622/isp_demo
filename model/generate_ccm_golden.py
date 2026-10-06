"""原始Bayer NPY经BLC->AWB->Demosaic->CCM生成严格RGB36黄金。"""
import argparse
from pathlib import Path
import numpy as np
from model.isp_model import run_pipeline


def main():
    # 路径先解析；数字配置在删除旧目标后的保护区内验证，错误矩阵不能
    # 留下旧黄金。matrix使用变长字符串参数，再严格检查九个十进制整数。
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',required=True)
    parser.add_argument('--output',required=True)
    parser.add_argument('--black-level',required=True)
    for channel in 'rgb': parser.add_argument('--gain-'+channel,required=True)
    parser.add_argument('--matrix',nargs='*',help='nine signed integer codes, row-major')
    args=parser.parse_args()
    output=Path(args.output)
    # 同名或软链接别名必须在任何删除动作之前拒绝，保护原始输入。
    if Path(args.input).resolve()==output.resolve(): parser.error('input and output must be distinct')
    try:
        if output.is_dir(): raise ValueError('output must be a file')
        output.parent.mkdir(parents=True,exist_ok=True)
        if output.exists(): output.unlink()
        if args.matrix is None or len(args.matrix)!=9: raise ValueError('matrix requires exactly nine integer codes')
        codes=[int(code) for code in args.matrix]
        config={'pipeline':{'blc':True,'awb_gain':True,'demosaic':True,'ccm':True},
                'blc':{'offset':int(args.black_level)},
                'awb_gain':{'r':int(args.gain_r),'g':int(args.gain_g),'b':int(args.gain_b)},
                'ccm':{'matrix':[codes[row*3:row*3+3] for row in range(3)]}}
        raw=np.load(args.input,allow_pickle=False)
        result=run_pipeline(raw,config)
        # 使用本帧真实二维尺寸展开；RGB三通道各12位，不加入SRAM填充位。
        with output.open('w',encoding='ascii') as stream:
            for r,g,b in result.reshape(-1,3):
                stream.write('{:09x}\n'.format((int(r)<<24)|(int(g)<<12)|int(b)))
    except (OSError,ValueError) as error:
        # 运算和写出失败都清理旧/部分目标；不会递归删除目录或源数据。
        if output.is_file(): output.unlink()
        parser.exit(2,'[FAIL] CCM golden generation: {}\n'.format(error))
    print('[PASS] CCM golden pixels={}'.format(result.shape[0]*result.shape[1]))


if __name__=='__main__': main()
