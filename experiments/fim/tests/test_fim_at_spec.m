function test_fim_at_spec()
% Boundary tests for the FIM profile, independently using dp_taliro.
paths=fim_paths(); repo=paths.Repo; oldPath=path;
cleanup=onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(fullfile(repo,'s-taliro','dp_taliro'));
s=fim_at_spec(); p=s.Preds;
middle=mean(s.OutputRange,2); half=diff(s.OutputRange,1,2)/2;
for k=1:numel(p)
    p(k).A=s.Preds(k).A*diag(half);
    p(k).b=s.Preds(k).b-s.Preds(k).A*middle;
end
assert(height(s.Faults)==10 && numel(unique(s.Faults.ID))==10);
assert(isequal(s.InputRange,[0 100;0 325]));
samples=[600 0 1;6000 160 4;598 0 1;6002 0 1;1000 0 0;1000 0 5; ...
    599 0 1;6001 0 1;1000 0 0.5;1000 0 4.5];
expected=[1/3000;1/3000;-1/3000;-1/3000;-1/3;-1/3;0;0;0;0];
for k=1:size(samples,1)
    y=repmat((samples(k,:)-middle')./half',31,1);
    rho=dp_taliro(s.Formula,p,y,(0:30)',[],[],[]);
    assert(abs(rho-expected(k))<1e-10,'Predicate test %d failed.',k);
end
y=repmat(([1000 0 1]-middle')./half',31,1);
y(end,1)=(6002-middle(1))/half(1);
assert(dp_taliro(s.Formula,p,y,(0:30)',[],[],[])<0, ...
    'The closed horizon must include t=30.');
fprintf('PASS: FIM specification, normal bounds, four violations, zero boundaries, endpoint.\n');
end
