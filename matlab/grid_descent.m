mname = 'TX28';
datexp = '2018_10_02';
blk = '1';

spks = readNPY(sprintf('Z:/data/PROC/%s/%s/%s/suite2p/combined/spks.npy', mname, datexp, blk));

iscell = readNPY(sprintf('Z:/data/PROC/%s/%s/%s/suite2p/combined/iscell.npy', mname, datexp, blk));
spks = spks(logical(iscell(:,1)), :);
[NN, Nframes] = size(spks);
%%
X = readNPY('D:\Github\rastercode\imgcov.npy');
X = zscore(X, [], 2);

%%
X = readNPY('D:/Github/data/allen-visp-alm/X.npy');
X = zscore(X(1:3:end, :), [], 2);
U = gpuArray(single(X));
%%
X = gpuArray(single(spks));
X = zscore(X, [], 2);
%X = X - mean(X, 1) ;

Lblock = 128;
inds = 1:size(X,2);
iblock = ceil(inds/Lblock);
nblocks = max(iblock);
iperm = randperm(nblocks);

Ntrain = ceil(3/4 * nblocks);
itrain = ismember(iblock, iperm(1:Ntrain));
itest  = ismember(iblock, iperm(1+Ntrain:nblocks));

X1 = X(:, itrain);
Xz = X(:, itest);
%%
[U, S, V] = svdecon(X);
U = U .* diag(S)';

U = gpuArray(U(:, 1:256));
U = 3.4 * zscore(U, 1, 2);
%%
ngrid = 41^2;
ys = .1 * U(:, 1:ndims);
zs = ys(randperm(NN, ngrid), :);

ndims = 2;
niter = 4000;
eta0 = .005;
pW = 0.9;

NN = size(U,1);
ys = gpuArray(single(ys));
zs = gpuArray(single(zs));

dy = gpuArray.zeros(NN, ndims, 'single');
dz = gpuArray.zeros(ngrid, ndims, 'single');

err0 = mean(U(:).^2);
eta = linspace(eta0, eta0, niter);
lam = ones(NN,1);
oy = zeros(NN, ndims);
oz = zeros(ngrid, ndims);

cold = Inf;
tic
for k = 1:niter
    ds = gpuArray.zeros(NN, ngrid, 'single');
    for j = 1:ndims
        ds = ds + (ys(:,j) - zs(:,j)').^2;
    end
    
    S = exp(-ds);     
    S = S./sum(S.^2, 1).^.5;
    
    A = S' * U;
    ypred = S * A;
    
    lam = mean(ypred .* U, 2) ./ (1e-4 + mean(ypred.^2, 2));        
    err = lam .* ypred - U;
    if rem(k,100)==1
        cnew = mean(err(:).^2)/err0;        
        fprintf('iter %d, eta %2.2f, time %2.2f, err %2.6f \n', k, eta(k),  toc, cnew)
    end    
    err = lam.*err;
    err = err * A' + U * (err' * S);
    
    for j = 1:ndims
       err2 = err .* (ys(:,j) - zs(:,j)');       
       dy(:,j) = - mean(err2, 2);         
       dz(:,j) = mean(err2, 1);
    end
    dy = dy./sum(dy.^2,2).^.5;
    dz = dz./sum(dz.^2,2).^.5;
    
    oy = pW * oy + (1-pW) * dy;
    oz = pW * oz + (1-pW) * dz;
    ys = ys - eta(k) * oy;
    zs = zs - eta(k) * oz;
end
toc

plot(ys(:,1), ys(:,2), '.')
drawnow
%%
ds = reshape(ys, [NN, 1, ndims]) - reshape(ys, [1, NN, ndims]);
W = exp(-sum(ds.^2, 3));
W = W - diag(diag(W));
W = gather(W);
[~, isort] = sort(W, 2, 'descend');
Xz = zscore(Xz, [], 2)/size(Xz,2)^.5;
X0 = gpuArray.zeros(size(Xz), 'single');
cb = zeros(128,1);
for j = 1:128
    X0 = X0 + Xz(isort(:, j),:);
    X0z = zscore(X0, [], 2)/size(X0,2)^.5;
    cc = sum(Xz .* X0z, 2);
    cb(j) = gather(mean(cc));
end

cb(1)
semilogx(cb)
