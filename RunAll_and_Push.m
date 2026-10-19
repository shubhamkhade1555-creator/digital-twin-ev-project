function result = RunAll_and_Push(varargin)
%RUNALL_AND_PUSH  RunAll, then send the Black Box run to the website. Same options as RunAll.
result = RunAll(varargin{:});
try
    push_to_website([], [], 'RunAll');
catch err
    warning('RunAll_and_Push:push','The run finished, but the website upload failed: %s', err.message);
end
end
