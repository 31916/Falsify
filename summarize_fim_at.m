function summary = summarize_fim_at(runDirectory)
%SUMMARIZE_FIM_AT Compact, auditable report and representative waveforms.
spec=fim_at_spec();
a=readtable(fullfile(runDirectory,'experiment1.csv'),'TextType','string');
b=readtable(fullfile(runDirectory,'experiment2.csv'),'TextType','string');
assert(height(a)==132 && height(b)==66,'Both experiments must be complete.');
ids=["B00";string(spec.Faults.ID)];
summary=table(ids,zeros(11,1),zeros(11,1),zeros(11,1),zeros(11,1), ...
    zeros(11,1),zeros(11,1),'VariableNames', ...
    {'Case','Exp1ViolatingInputs','Exp1MinRho','RANDSuccesses','ACERSuccesses','RANDEpisodes','ACEREpisodes'});
for k=1:numel(ids)
    aa=a(a.Case==ids(k),:); rr=b(b.Case==ids(k)&b.Algorithm=="RAND",:);
    cc=b(b.Case==ids(k)&b.Algorithm=="ACER",:);
    assert(height(aa)==12 && height(rr)==3 && height(cc)==3);
    summary.Exp1ViolatingInputs(k)=sum(aa.Violated);
    summary.Exp1MinRho(k)=min(aa.Rho);
    summary.RANDSuccesses(k)=sum(rr.Violated);
    summary.ACERSuccesses(k)=sum(cc.Violated);
    summary.RANDEpisodes(k)=sum(rr.Episodes);
    summary.ACEREpisodes(k)=sum(cc.Episodes);
end
assert(~any(a.Violated(a.Case=="B00")) && ~any(b.Violated(b.Case=="B00")));
assert(all(b.BaselineRho>0));
writetable(summary,fullfile(runDirectory,'summary.csv'));
file=fullfile(runDirectory,'REPORT.md');
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# FIM / AT 実験結果\n\n');
fprintf(fid,'要件: □[0,30](599 < RPM < 6001 ∧ 0.5 < gear < 4.5)。');
fprintf(fid,' ARCH2025 の元要件とは異なる FIM 専用要件です。\n\n');
fprintf(fid,'入力: throttle [0,100], brake [0,325]、5秒刻み区分定数、30秒。');
fprintf(fid,' 各故障は5秒から終了まで有効、1モデル1故障、10種類・3か所。\n\n');
fprintf(fid,'| ケース | 固定入力で違反 /12 | 最小ρ | RAND 発見 /3 | ACER 発見 /3 | RAND総試行 | ACER総試行 |\n');
fprintf(fid,'|---|---:|---:|---:|---:|---:|---:|\n');
for k=1:height(summary)
    fprintf(fid,'| %s | %d | %.7g | %d | %d | %d | %d |\n', ...
        summary.Case(k),summary.Exp1ViolatingInputs(k),summary.Exp1MinRho(k), ...
        summary.RANDSuccesses(k),summary.ACERSuccesses(k), ...
        summary.RANDEpisodes(k),summary.ACEREpisodes(k));
end
fprintf(fid,'\n正常系は固定12入力および探索で違反なし。');
fprintf(fid,' 全探索候補を独立FIMモデルと正常モデルで再実行し、正常側のρ > 0を確認。\n\n');
fprintf(fid,'- 実験1: 132モデル×入力組合せ。別途120回の故障OFF検査。\n');
fprintf(fid,'- 実験2: 66探索ラン、合計%dエピソード（各ラン最大10、seed 101/202/303）。\n',sum(b.Episodes));
fprintf(fid,'- 故障OFFと正常系の最大差: %.9g。故障発生前の最大差: %.9g。\n',max(a.FaultOffMaxError),max(a.BeforeFaultMaxError));
fprintf(fid,'- FIM指定演算とログの最大差: %.9g。\n',max(a.InjectionMaxError));
fprintf(fid,'- 各探索ランの最良候補について、ラッパーと再実行の最大差: %.9g。\n',max(b.ReplayMaxError));
fprintf(fid,'- ρはRPM距離/3000とgear距離/1.5の最小値。物理単位の各余裕はMATに保存。\n');
fprintf(fid,'\n## 解釈と制約\n\n');
fprintf(fid,'正常系の範囲成立はEngine積分器の飽和とgear状態の代入値から説明できますが、');
fprintf(fid,'形式検証の証明書はありません。有限個の実験結果だけによる全入力保証ではありません。\n\n');
fprintf(fid,'未発見は「故障なし」でも「安全の証明」でもありません。');
fprintf(fid,'Tout内部故障は回転数制限・gear範囲を保つことがあり、この要件では検出できません。');
fprintf(fid,'また単純な観測故障は容易に検出されるため、これだけで学習手法の優位性は示せません。');
fprintf(fid,'Ψ-TaLiRoとの比較は未実施です。\n\n');
fprintf(fid,'[故障カタログ](fault_catalog.csv)、[実験1](experiment1.csv)、[実験2](experiment2.csv)、');
fprintf(fid,'[集計](summary.csv)、[代表波形](comparison.png)。');
fprintf(fid,' 全入力・波形・探索履歴はexp1/とexp2/のMAT、生成根拠はgeneration_F*/fault_table/。\n');
% Pick informative cases using a documented deterministic selection rule.
fig=figure('Visible','off','Position',[100 100 1200 950],'Color','white');
if isprop(fig,'Theme'), fig.Theme='light'; end
figCleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
choices={"F02",1;'F07',3;'F10',2};
for j=1:3
    id=string(choices{j,1}); column=choices{j,2};
    candidates=a(a.Case==id,:); [~,idx]=min(candidates.Rho);
    input=candidates.Input(idx);
    if id=="F10", input="U02"; end
    x=load(fullfile(runDirectory,'exp1',char(id+"_"+input+".mat")));
    ax=nexttile(layout);
    plot(ax,x.baseline.T,x.baseline.Y(:,column),'Color',[0.12 0.35 0.70],'LineWidth',1.4); hold(ax,'on');
    plot(ax,x.trace.T,x.trace.Y(:,column),'Color',[0.8 0.18 0.1],'LineWidth',1.3);
    xline(ax,5,':','Fault ON','HandleVisibility','off');
    if column==1
        yline(ax,6001,'--','Upper requirement','HandleVisibility','off'); ylabel(ax,'RPM');
    elseif column==3
        yline(ax,4.5,'--','Upper requirement','HandleVisibility','off'); ylabel(ax,'Gear'); ylim(ax,[0.5 5.5]);
    else, ylabel(ax,'Speed (mph)'); end
    title(ax,sprintf('%s / %s : rho = %.5g',id,input,x.trace.Rho));
    legend(ax,{'Baseline','FIM fault'},'Location','best'); grid(ax,'on'); xlim(ax,[0 30]);
end
xlabel(ax,'Time (s)');
title(layout,'FIM / AT: signal faults can violate the invariant; torque faults need not');
exportgraphics(fig,fullfile(runDirectory,'comparison.png'),'Resolution',150,'BackgroundColor','white');
disp(summary);
end
