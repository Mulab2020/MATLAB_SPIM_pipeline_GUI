function index = binary_search(sorted, value)
% BINARY_SEARCH  Find the insertion point of a value in an ascending vector.
%
%   index = util.binary_search(sorted, value)
%
% Returns the index of the largest element of `sorted` that is <= value.
% `sorted` must be a 1D vector in ascending order. The returned index is
% the position after which `value` should be inserted; when several
% elements equal `value`, one of them is located.
%
% Used by util.rolling_percentile_filter to update its running sorted
% window: the outgoing sample is located for removal, and the incoming
% sample's insertion point is found.
%
% Algorithm ported from common_20210823/new pipeline.
%
% See also util.rolling_percentile_filter

    l = 1;
    r = length(sorted);
    while l < r
        index = 1 + floor((l + r - 1) / 2);
        if sorted(index) > value
            r = index - 1;
        elseif sorted(index) <= value
            l = index;
        end
    end
    if l == r
        index = r;
    end
end
