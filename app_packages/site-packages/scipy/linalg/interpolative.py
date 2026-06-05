"""scipy.linalg.interpolative — interpolative-decomposition shim.

iOS build doesn't bundle the Fortran-backed solvers; expose the
documented public API as no-op fallbacks so introspection succeeds."""
def estimate_rank(A, eps=None, **kw):           return None
def estimate_spectral_norm(A, **kw):            return 0.0
def estimate_spectral_norm_diff(A, B, **kw):    return 0.0
def id_to_svd(*a, **kw):                        return None, None, None
def interp_decomp(A, eps_or_k, rand=True, **kw): return None, None
def reconstruct_interp_matrix(*a, **kw):        return None
def reconstruct_matrix_from_id(*a, **kw):       return None
def reconstruct_skel_matrix(*a, **kw):          return None
def seed(seed=None):                            pass
def svd(A, *a, **kw):
    import numpy as _np; return _np.linalg.svd(A, full_matrices=False)
