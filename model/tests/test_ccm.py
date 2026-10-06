"""CCM 模型验收：独立 Python 整数 oracle、手算与严格接口检查。"""
import itertools
import unittest
import numpy as np
from model.ccm import apply_ccm, IDENTITY_MATRIX
from model.isp_model import run_pipeline

A = IDENTITY_MATRIX
B = ((0,0,4096),(0,4096,0),(4096,0,0))
C = ((5120,-512,-512),(-256,4608,-256),(-512,-512,5120))
D = ((8192,0,0),(0,-4096,8192),(-4096,0,8192))
ASYMMETRIC = ((4096,2048,0),(0,4096,-1024),(1024,0,4096))


def oracle(rgb, matrix):
    """Python 无限精度逐项乘加；商/余数舍入独立于 NumPy 矩阵与偏置写法。"""
    result = np.empty(rgb.shape, dtype=np.uint16)
    for index in np.ndindex(rgb.shape[:2]):
        for row in range(3):
            total = sum(int(rgb[index][col])*int(matrix[row][col]) for col in range(3))
            quotient, remainder = divmod(total, 4096)
            result[index][row] = 0 if total <= 0 else min(quotient+int(remainder >= 2048),4095)
    return result


class CCMTests(unittest.TestCase):
    def test_boundary_cartesian_and_independent_oracle(self):
        pixels = np.array(list(itertools.product((0,1,2047,2048,4094,4095), repeat=3)), dtype=np.uint16).reshape(12,18,3)
        matrices = (A,B,C,D,ASYMMETRIC,((0,)*3,)*3,((2048,)*3,)*3,
                    ((6144,-2048,0),)*3,((32767,)*3,)*3,((-32768,)*3,)*3,
                    ((32767,-32768,1),)*3)
        for matrix in matrices:
            np.testing.assert_array_equal(apply_ccm(pixels,matrix), oracle(pixels,matrix))

    def test_asymmetric_hand_calculation(self):
        np.testing.assert_array_equal(apply_ccm([[[1000,2000,3000]]],ASYMMETRIC), [[[2000,1250,3250]]])
        np.testing.assert_array_equal(apply_ccm([[[72,18,54]]],C), [[[81,12,56]]])

    def test_rounding_neighbors_and_saturation(self):
        for code, wanted in ((1,0),(2047,0),(2048,1),(2049,1),(4095,1),(4096,1),(4097,1)):
            self.assertEqual(int(apply_ccm([[[1,0,0]]],((code,0,0),)*3)[0,0,0]),wanted)
        np.testing.assert_array_equal(apply_ccm([[[4095,0,0]]],((4097,0,0),)*3), [[[4095]*3]])

    def test_signed_cancellation_and_clamp(self):
        pixels = np.array([[[4095,4095,4095],[4095,4094,0],[1,2,0]]],dtype=np.uint16)
        for matrix in (((32767,-32768,1),)*3,((-4096,4096,0),)*3,D):
            np.testing.assert_array_equal(apply_ccm(pixels,matrix),oracle(pixels,matrix))

    def test_seeded_full_range_and_no_mutation(self):
        rng=np.random.RandomState(5)
        pixels=rng.randint(0,4096,(7,9,3)).astype(np.uint16)
        matrix=rng.randint(-32768,32768,(3,3)).astype(np.int16)
        before, saved = pixels.copy(), matrix.copy()
        result=apply_ccm(pixels,matrix)
        np.testing.assert_array_equal(result,oracle(pixels,matrix))
        np.testing.assert_array_equal(pixels,before)
        np.testing.assert_array_equal(matrix,saved)
        self.assertEqual(result.dtype,np.uint16)
        self.assertFalse(np.shares_memory(result,pixels))

    def test_invalid_matrix_shape_type_range(self):
        invalid=(0,[],[1,2,3],[[1,2],[3,4]],np.zeros((3,3,1)),
                 [[True,0,0],[0,4096,0],[0,0,4096]],
                 [[4096.0,0,0],[0,4096,0],[0,0,4096]],
                 [[np.bool_(False),0,0],[0,4096,0],[0,0,4096]],
                 [[32768,0,0],[0,0,0],[0,0,0]],[[-32769,0,0],[0,0,0],[0,0,0]],
                 [['4096',0,0],[0,0,0],[0,0,0]])
        for matrix in invalid:
            with self.assertRaises(ValueError): apply_ccm([[[1,2,3]]],matrix)

    def test_invalid_rgb(self):
        for rgb in (0,[],[[1,2,3]],np.empty((0,2,3)),np.zeros((1,1,4)),
                    [[[1.0,2,3]]],[[[True,False,True]]],[[[-1,0,0]]],[[[4096,0,0]]]):
            with self.assertRaises(ValueError): apply_ccm(rgb,A)

    def test_pipeline_order_defaults_and_compatibility(self):
        raw=np.full((2,2),100,dtype=np.uint16)
        cfg={'pipeline':{'blc':True,'awb_gain':True,'demosaic':True,'ccm':True},
             'blc':{'offset':64},'awb_gain':{'r':8192,'g':2048,'b':6144},'ccm':{'matrix':C}}
        np.testing.assert_array_equal(run_pipeline(raw,cfg),np.tile([81,12,56],(2,2,1)))
        del cfg['ccm']
        np.testing.assert_array_equal(run_pipeline(raw,cfg),np.tile([72,18,54],(2,2,1)))
        self.assertIs(run_pipeline(raw,{}),raw)
        with self.assertRaises(ValueError): run_pipeline(raw,{'pipeline':{'ccm':True}})


if __name__ == '__main__': unittest.main()
