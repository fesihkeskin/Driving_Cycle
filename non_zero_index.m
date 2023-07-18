% Function for finding first and last non-zero elements in a given array
function [start_of_cycle, end_of_cycle] = non_zero_index(array)
% Find the index of the first non-zero element
start_of_cycle = find(array ~= 0, 1);
% Find the index of the last non-zero element
end_of_cycle = find(array ~= 0, 1, 'last');
end