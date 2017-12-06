# FWI on Overthrust model using minConf library 
# Author: Philipp Witte, pwitte@eoas.ubc.ca
# Date: May 2017
#

using PyCall, HDF5, opesciSLIM.TimeModeling, opesciSLIM.SLIM_optim, SeisIO, PyPlot, JLD

# Load starting model
n,d,o,m0 = read(h5open("/scratch/slim/pwitte/models/overthrust_mini.h5","r"), "n", "d", "o", "m0")
model0 = Model((n[1],n[2]), (d[1],d[2]), (o[1],o[2]), m0)

# Bound constraints
v0 = sqrt.(1./model0.m)
vmin = ones(Float32,model0.n) * 1.3f0
vmax = ones(Float32,model0.n) * 6.5f0
vmin[:,1:21] = v0[:,1:21]	# keep water column fixed
vmax[:,1:21] = v0[:,1:21]

# Slowness squared [s^2/km^2]
mmin = vec((1f0./vmax).^2)
mmax = vec((1f0./vmin).^2)

# Load data
block = segy_read("/scratch/slim/pwitte/overthrust2D/overthrust_mini.segy")
d_obs = joData(block)

# Set up wavelet
src_geometry = Geometry(block; key="source")#, segy_depth_key="SourceDepth")
wavelet = ricker_wavelet(src_geometry.t[1],src_geometry.dt[1],0.008f0)	# 8 Hz wavelet
q = joData(src_geometry,wavelet)

############################### FWI ###########################################

# Set up operators
ntComp = get_computational_nt(q.geometry,d_obs.geometry,model0)	# no. of computational time steps
info = Info(prod(model0.n),d_obs.nsrc,ntComp)
Pr = joProjection(info,d_obs.geometry)
Ps = joProjection(info,q.geometry)
F = joModeling(info,model0)
J = joJacobian(Pr*F*Ps',q)

# Optimization parameters
batchsize = 4
maxiter = 10
maxiter_GN = 5
fhistory_GN = zeros(Float32,maxiter)
proj(x) = reshape(median([vec(mmin) vec(x) vec(mmax)],2),model0.n)

# Gauss-Newton method
for j=1:maxiter
    println("Iteration: ",j)

    # Model predicted data for subset of sources
    i = randperm(d_obs.nsrc)[1:batchsize]
    d_pred = Pr[i]*F[i]*Ps[i]'*q[i]
    fhistory_GN[j] = .5f0*norm(d_pred - d_obs[i])^2
                        
    # GN update direction
    p = zeros(Float32, info.n)
    for k=1:maxiter_GN
        println("    GN iteration: ",k)
        r = J[i]*p - (d_pred - d_obs[i])
        g_gn = J[i]'*r
        t = norm(r)^2/norm(g_gn)^2    # step size
        p -= t*g_gn
    end
                                                                                
    # update model and bound constraints
    model0.m = proj(model0.m - reshape(p, model0.n))    # alpha=1
    figure(); imshow(sqrt.(1f0./model0.m)')
end


