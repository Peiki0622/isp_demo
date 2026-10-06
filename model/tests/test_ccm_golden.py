"""CCM黄金CLI：独立手算全链、真实raster及失败清除旧目标。"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
SCRATCH=ROOT/'build/p5_ccm/python'
C=(5120,-512,-512,-256,4608,-256,-512,-512,5120)


class CCMGoldenTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=str(SCRATCH))
        self.addCleanup(self.temp.cleanup)
        self.source=Path(self.temp.name)/'input.npy'
        self.output=Path(self.temp.name)/'golden.mem'
        np.save(str(self.source),np.full((2,2),100,dtype=np.uint16))

    def generate(self,matrix=C,black=64,gains=(8192,2048,6144)):
        # 保留真实进程入口，捕获退出码和诊断，不能直接调用模型掩盖CLI行为。
        args=[sys.executable,'-m','model.generate_ccm_golden','--input',str(self.source),
              '--output',str(self.output),'--black-level',str(black)]
        for channel,gain in zip('rgb',gains): args+=['--gain-'+channel,str(gain)]
        if matrix is not None: args+=['--matrix']+[str(code) for code in matrix]
        return subprocess.run(args,cwd=str(ROOT),stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True)

    def test_exact_four_stage_hand_golden(self):
        result=self.generate()
        self.assertEqual(result.returncode,0,result.stderr)
        # BLC/AWB/Demosaic=(72,18,54)，矩阵C=(81,12,56)，四像素逐行九位。
        self.assertEqual(self.output.read_text(),'05100c038\n'*4)
        self.assertIn('pixels=4',result.stdout)

    def test_actual_raster_and_non_symmetric_matrix(self):
        np.save(str(self.source),np.array([[100,30],[50,200]],dtype=np.uint16))
        matrix=(4096,2048,0,0,4096,-1024,1024,0,4096)
        result=self.generate(matrix,0,(4096,4096,4096))
        self.assertEqual(result.returncode,0,result.stderr)
        expected=[]
        # 四个demosaic中心的值为独立已手算结果，非调用正式软件模块。
        for rgb in ((100,40,200),(100,30,200),(100,50,200),(100,40,200)):
            channels=[]
            for row in range(3):
                total=sum(rgb[col]*matrix[row*3+col] for col in range(3))
                q,r=divmod(total,4096)
                channels.append(0 if total<=0 else min(q+int(r>=2048),4095))
            expected.append('{:03x}{:03x}{:03x}\n'.format(*channels))
        self.assertEqual(self.output.read_text(),''.join(expected))

    def test_invalid_matrix_removes_stale(self):
        for matrix in (None,(),C[:8],C+(0,),('1.0',)+C[1:],('True',)+C[1:],(32768,)+C[1:],(-32769,)+C[1:]):
            self.output.write_text('stale\n')
            result=self.generate(matrix)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('[FAIL] CCM golden generation',result.stderr)
            self.assertFalse(self.output.exists())

    def test_invalid_raw_removes_stale(self):
        for raw in (np.zeros((1,2)),np.zeros((2,1)),np.empty((0,2)),np.ones((2,2),dtype=float),
                    np.array([[-1,0],[0,0]]),np.array([[4096,0],[0,0]]),np.zeros((2,2,3))):
            np.save(str(self.source),raw);self.output.write_text('stale\n')
            self.assertNotEqual(self.generate().returncode,0)
            self.assertFalse(self.output.exists())

    def test_invalid_blc_awb_removes_stale(self):
        for black,gains in ((-1,(4096,)*3),(4096,(4096,)*3),('1.0',(4096,)*3),
                            (0,(-1,4096,4096)),(0,(4096,65536,4096)),(0,(4096,4096,'1.0'))):
            self.output.write_text('stale\n')
            self.assertNotEqual(self.generate(C,black,gains).returncode,0)
            self.assertFalse(self.output.exists())

    def test_missing_input_removes_stale(self):
        self.source.unlink();self.output.write_text('stale\n')
        self.assertNotEqual(self.generate().returncode,0)
        self.assertFalse(self.output.exists())

    def test_same_source_destination_preserved(self):
        self.output=self.source
        before=self.source.read_bytes()
        self.assertNotEqual(self.generate().returncode,0)
        self.assertEqual(self.source.read_bytes(),before)


if __name__=='__main__': unittest.main()
