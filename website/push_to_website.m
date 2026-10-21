function push_to_website(siteUrl, apiKey, runName)
%PUSH_TO_WEBSITE  Send the last Black Box run (EV_BlackBox_log) to the website.
%   push_to_website                        uses EV_Website_Config.m (created by Setup_All)
%   push_to_website(url, key, 'RunAll')    explicit values
if nargin < 3 || isempty(runName), runName = 'RunAll'; end
if nargin < 2 || isempty(siteUrl) || isempty(apiKey)
    if exist('EV_Website_Config','file') ~= 2
        error('push_to_website:config','Run Setup_All first (it creates EV_Website_Config.m) or pass siteUrl and apiKey.');
    end
    cfg = EV_Website_Config();  siteUrl = cfg.siteUrl;  apiKey = cfg.apiKey;
end
siteUrl = regexprep(char(siteUrl), '/+$', '');
bb  = evalin('base','EV_BlackBox_log');
try
    lab = cellstr(get_param('BLDCSpeedControl_EV_Layout_v2/EV_BlackBox','UserData'));
catch
    lab = {'Vbatt_V','Ibatt_A','SOC','RPM_rpm','Idc_f_A','Vdc_m_V','omega_wheel','Torque_Nm'};
end
data = bb.Data;
if size(data,2) ~= numel(lab)
    error('push_to_website:cols','EV_BlackBox_log has %d columns but %d labels.', size(data,2), numel(lab));
end
from = {'RPM_rpm','Idc_f_A','Torque_Nm','Vbatt_V','Ibatt_A','SOC','Vdc_m_V','omega_wheel'};
to   = {'rpm','i','T','vb','ib','soc','vdc','ww'};
d = struct();
for k = 1:numel(lab)
    j = find(strcmp(lab{k}, from), 1);
    if ~isempty(j), d.(to{j}) = data(:,k)'; end
end
p = struct('rpmRef',getv('rpm_ref',2950), 'ramp',getv('rpm_ramp',13000), 'load',getv('load_scale',1), ...
           'Ipeak',getv('I_peak',45), 'tstop',bb.Time(end));
payload = struct('source','matlab','name',runName,'p',p,'t',bb.Time(:)','d',d);
opts = weboptions('MediaType','application/json','RequestMethod','post','Timeout',60, ...
                  'HeaderFields',{'x-api-key', apiKey});
r = webwrite([siteUrl '/api/runs'], payload, opts);
fprintf('[push_to_website] run %s saved (%s, storage: %s)\n', r.id, r.result, r.storage);
if strcmp(r.storage,'memory')
    warning('push_to_website:memory','The website keeps runs in memory only. Connect a Vercel Blob store (see website/README.md).');
end
end

function v = getv(name, def)
try, v = double(evalin('base', name)); catch, v = def; end
end
