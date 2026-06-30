
function [filelist, nFiles] = GetAllFileNames(pathname, ext, fileind, textInName, textNotInName)

% get all file names with 'ext'



if nargin < 3, fileind = []; end
if nargin < 4, textInName = ''; end
if nargin < 5, textNotInName = ''; end

if exist(pathname)  == 7 % directory
    %% list directory
    pathstr = pathname;
    list = dir(pathname); 
    list(1:2)=[];  % remove '.' and '..'
    filelist = {list.name};
    if isempty(filelist)
        error('No files found at path %s', pathname);
    end

    %% first restrict by indices passed in
    if ~isempty(fileind)
        filelist = filelist(fileind);
    end
    
    %% remove files with other extensions
    rMatchNs = regexpi(filelist, ['\.(', ext, ')$']);
    filelist = filelist(~cellfun(@isempty, rMatchNs));
    
    %% restrict list by text str if necessary
    if ~isempty(textInName)
        rMatchNs = regexpi(filelist, textInName);
        filelist = filelist(~cellfun(@isempty, rMatchNs));
    end
    if ~isempty(textNotInName)
        rMatchNs = regexpi(filelist, textNotInName);
        filelist = filelist(cellfun(@isempty, rMatchNs));
    end
        
    %---  must have full list by the time we hit here, sorting below

    nFiles = length(filelist);

    %% check number resulting
    fprintf(1,'Found %i files \n', nFiles);
 
else  % could not find directory/file
    error('pathname does not exist: %s', pathname);
end