"""CPU port of ARCH repeatability ExternalGPR; same kernel/data/fit settings.

Source: ARCH-Comp-2024-Repeatability 537de595, ConBOExp/benchmarks/gpr_external.py.
Only CUDA placement and the equivalent interface import differ. In particular,
the source's unscaled Y fit is intentionally preserved (not silently corrected).
"""
import numpy as np
import torch
import gpytorch
from botorch import fit_gpytorch_model
from gpytorch.kernels import MaternKernel
from sklearn.preprocessing import StandardScaler
from lsemibo.gprInterface import GaussianProcessRegressorStructure


class ExactGPModel(gpytorch.models.ExactGP):
    def __init__(self, train_x, train_y, likelihood, kernel):
        super().__init__(train_x, train_y, likelihood)
        self.mean_module = gpytorch.means.ZeroMean()
        self.covar_module = kernel

    def forward(self, x):
        return gpytorch.distributions.MultivariateNormal(
            self.mean_module(x), self.covar_module(x))


class ExternalGPRCPU(GaussianProcessRegressorStructure):
    def __init__(self):
        self.scale = StandardScaler()
        self.scaley = StandardScaler()
        self.kernel = MaternKernel()
        self.kernel.lengthscale = 1

    def fit_gpr(self, X, Y):
        x = torch.from_numpy(self.scale.fit_transform(X))
        self.scaley.fit_transform(np.asarray([Y]).T)
        y = torch.from_numpy(Y)
        self.likelihood = gpytorch.likelihoods.GaussianLikelihood()
        self.model = ExactGPModel(x, y, self.likelihood, self.kernel)
        self.model.train()
        self.likelihood.train()
        self.mll = gpytorch.mlls.ExactMarginalLogLikelihood(self.likelihood, self.model)
        fit_gpytorch_model(self.mll)

    def predict_gpr(self, X):
        x = torch.from_numpy(self.scale.transform(X))
        self.model.eval()
        self.likelihood.eval()
        with torch.no_grad(), gpytorch.settings.fast_pred_var():
            result = self.likelihood(self.model(x))
        return result.mean.numpy(), result.stddev.numpy()
