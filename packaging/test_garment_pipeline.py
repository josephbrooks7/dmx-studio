import unittest
from body_fit import Section
from garment_regions import Frame,Region
from garment_clearance import SurfaceSample
from garment_pipeline import fit_garment

class PipelineTests(unittest.TestCase):
    def run_fit(self, **overrides):
        f=Frame.from_landmarks((0,0,0),(0,1,0),(0,0,1))
        a=(Section(0,0,0,.1,.1),Section(1,0,0,.1,.1))
        b=(Section(0,0,0,.2,.1),Section(1,0,0,.2,.1))
        args=dict(vertices=[(.1,.5,0)],assignments=[{"torso":1}],
            regions={"torso":Region(f,f,a,b)},surface_regions=["torso"],
            surface_samples=[SurfaceSample((.2,.5,0),(1,0,0),"torso")],
            body_vertices=[(.2,.5,0)],body_weights=[{"spine":1}],
            bone_map={},target_bones={"spine"})
        args.update(overrides)
        return fit_garment(**args)
    def test_complete_pipeline(self):
        r=self.run_fit()
        self.assertAlmostEqual(r.vertices[0][0],.205)
        self.assertEqual(r.weights,({"spine":1.0},))
        self.assertTrue(r.ready_for_review)
    def test_strict_rejects_unresolved(self):
        with self.assertRaisesRegex(ValueError,"Unresolved"):
            self.run_fit(max_correction=0)
    def test_diagnostic_mode(self):
        r=self.run_fit(max_correction=0,strict=False)
        self.assertEqual(r.unresolved,(0,))
        self.assertFalse(r.ready_for_review)
    def test_empty_garment(self):
        with self.assertRaisesRegex(ValueError,"Empty"):
            self.run_fit(vertices=[])
    def test_no_skin_match(self):
        with self.assertRaises(ValueError):
            self.run_fit(body_vertices=[(4,4,4)])
if __name__=="__main__": unittest.main()
