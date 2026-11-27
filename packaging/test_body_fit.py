import unittest
from body_fit import Section, fit_vertices

class FitTests(unittest.TestCase):
    def setUp(self):
        self.a=[Section(0,0,0,1,1),Section(1,0,0,1,1)]
        self.b=[Section(0,0,0,2,3),Section(2,0,0,2,3)]
    def test_identity(self):
        p=[(1,.5,-1)]
        self.assertEqual(fit_vertices(p,self.a,self.a),p)
    def test_proportions(self):
        self.assertEqual(fit_vertices([(1,.5,-1)],self.a,self.b),[(2,1,-3)])
    def test_outside(self):
        with self.assertRaises(ValueError):
            fit_vertices([(1,2,0)],self.a,self.b)
    def test_invalid_sections(self):
        with self.assertRaises(ValueError):
            fit_vertices([],self.a,list(reversed(self.b)))
    def test_clearance(self):
        self.assertEqual(fit_vertices([(1,.5,0)],self.a,self.a,.125),[(1.125,.5,0)])

if __name__=="__main__":
    unittest.main()
