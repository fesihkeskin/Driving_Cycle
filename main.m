clear all;
close all;
clc;

% Set the data folder path
data_folder = "C:\path\to\data\";

% Get the file information for all .txt files in the data folder
file_info = dir(fullfile(data_folder, '*.txt'));
file_names = {file_info.name};

% Initialize variables for number of cycles and segments
num_cycles = length(file_names);
num_segments = 6;
data_files = cell(1, num_cycles);

% Perform data preprocessing for each file
for i = 1:num_cycles
    % Load the data from the current file
    data = load(fullfile(data_folder, file_names{i}));
    data = data(:, 2); % Exclude indexing (first) column and measured acceleration (third) column

    % Find the start and end indices of the nonzero values
    [start_group_index, end_group_index] = non_zero_index(data);

    % Remove unnecessary waiting times at the beginning and end of cycles
    if start_group_index > 1
        start_group_index = start_group_index - 1;
    end
    if end_group_index < length(data)
        end_group_index = end_group_index + 1;
    end

    % Remove zeros from start and end
    data = data(start_group_index:end_group_index, :);

    % Save the preprocessed data into data_files
    data_files{i} = data;
end

% Calculate acceleration for each cylce as,
for i = 1:num_cycles
    for j = 1:length(data_files{1, i}) - 1
        data_files{1, i}(j, 2) = (data_files{1, i}(j + 1, 1) - data_files{1, i}(j, 1)) / 3.6;
    end
end

% Initialize variables for minimum and maximum accelerations
min_accs = zeros(1, num_cycles);
max_accs = zeros(1, num_cycles);

% Find the minimum and maximum accelerations for each cycle
for i = 1:num_cycles
    min_accs(i) = min(data_files{1, i}(:, end));
    max_accs(i) = max(data_files{1, i}(:, end));
end

% Find the overall minimum acceleration and maximum accelerations
min_acc = min(min_accs);
max_acc = max(max_accs);

% Calculate maximum speed decrease and maximum speed increase
max_speed_decrease = min_acc * 3.6;
max_speed_increase = max_acc * 3.6;


% Load sizes of the segments
% Segment sizes are determined by dynamic segmentation to partition the 
% original datasets into segments based on traffic conditions and road types.
load(fullfile(data_folder, 'segment_sizes'));

% Initialize variable for segments
segments = cell(1, numel(segment_sizes));

% Get segments from cycles according to the segment sizes
for i = 1:num_cycles
    driving_cycle = data_files{1, i};
    start_index = 1;
    for j = num_segments * (i - 1) + 1:num_segments * i
        end_index = start_index + segment_sizes(j) - 1;
        segments{j} = driving_cycle(start_index:end_index, :);
        start_index = end_index + 1;
    end
end

% Set speed and acceleration intervals
v_res = 2.5; % Speed interval 2.5 km/h
a_res = 0.25; % Acceleration interval 0.25 m/s^2

% Initialize variable for all segments
all_segments = cell(num_segments, num_cycles);

% Get micro-trips
k = 0;
for i = 1:num_cycles
    for j = 1:num_segments
        k = k + 1;
        all_segments{j, i} = cell2mat(segments(k));
    end
end

% Initialize variables for average first and last speeds
avg_first_speeds = zeros(1, num_segments);
avg_last_speeds = zeros(1, num_segments);

% Get average of the first and last speeds for each segment
for i = 1:num_segments
    avg_first_speeds(i) = mean(cellfun(@(x) x(1, 1), all_segments(i, :)));
    avg_last_speeds(i) = mean(cellfun(@(x) x(end, 1), all_segments(i, :)));
end

% Groups of combined segments
combined_segments_groups = cell(1, num_segments);
for i = 1:num_segments
    combined_segments_groups{i} = cat(1, all_segments{i, :});
end

% Compute the distance matrix and find the reference driving segment for
% each segment groups using Dynamic Time Warping (DTW)
dist_matrix = zeros(num_cycles);
total_dist = zeros(1, num_segments);
ref_seg = zeros(1, num_segments);
seg_start_speed = zeros(1, num_segments + 1);
seg_end_speed = zeros(1, num_segments + 1);

for seg = 1:num_segments
    k = 0;
    for i = 1:num_cycles
        for j = 1:num_cycles
            k = k + 1;
            x = all_segments{seg, i}(:, 1);
            y = all_segments{seg, j}(:, 1);
            dist_matrix(i, j) = dtw(x, y);
        end
    end

    [total_dist(seg), ref_seg(seg)] = min(sum(dist_matrix, 1));
    seg_start_speed(seg + 1) = all_segments{seg, ref_seg(seg)}(1, 1);
    seg_end_speed(seg + 1) = all_segments{seg, ref_seg(seg)}(end, 1);

    % To maintain reasonable acceleration limits, segments from the same
    % cycle are selected if the acceleration at the transition exceeds
    % the maximum acceleration or deceleration.
    if abs(seg_start_speed(seg + 1) - seg_end_speed(seg)) > max_speed_increase
        ref_seg(seg) = ref_seg(seg - 1);
    end
end

% Get the reference segment's lengths
ref_seg_lengths = zeros(1, num_segments);
for seg = 1:num_segments
    ref_seg_lengths(seg) = length(all_segments{seg, ref_seg(seg)});
end

% Set number of Monte Carlo trials
MCT = 10000;

% Initialize cell arrays for Monte Carlo trials
mct_cons_dc_speed = cell(num_segments, MCT);
last_speed= zeros(num_segments, MCT);
for seg = 1:num_segments
    data_states = combined_segments_groups{seg};

    % For the current segment group
    speed_data = data_states(:, 1); % Speed data
    avg_speed = mean(speed_data); % Average speed
    max_speed = max(speed_data); % Maximum speed
    min_speed = min(speed_data); % Minimum speed
    acc_data = data_states(:, 2); % Acceleration data
    avg_acc = mean(acc_data); % Average acceleration
    max_acc = max(acc_data); % Maximum acceleration
    min_acc = min(acc_data); % Minimum acceleration
    acc_lower_bound = floor(min_acc / a_res) * a_res;
    acc_upper_bound = ceil(max_acc / a_res) * a_res + a_res;
    speed_lower_bound = floor(min_speed / v_res) * v_res;
    speed_upper_bound = ceil(max_speed / v_res) * v_res + v_res;
    a_steps = (acc_lower_bound:a_res:acc_upper_bound);
    v_steps = (speed_lower_bound:v_res:speed_upper_bound);

    % Create States for Markov-Chain Model

    % State assignment of Speed-Acceleration pairs in segment groups
    data_length = length(speed_data); % Length of segment group
    group_index=1:data_length;
    group_states = zeros(data_length, 3);
    k = 0;

    for i = 1:length(v_steps) - 1
        L_v = v_steps(i); % Lower speed of state
        U_v = v_steps(i + 1); % Upper speed of state

        for j = 1:length(a_steps) - 1
            L_a = a_steps(j); % Lower Acc. of state
            U_a = a_steps(j + 1); % Upper Acc. of state
            k = k + 1;

            ind_a = group_index(data_states(:, 2) >= L_a & data_states(:, 2) < U_a); % Indices of Acc.
            ind_v = group_index(data_states(:, 1) >= L_v & data_states(:, 1) < U_v); % Indices of Speed

            matches = intersect(ind_a, ind_v);

            if isempty(matches)
                k = k - 1;
            end

            group_states(matches, 1) = k;
            group_states(matches, 2) = (L_v + U_v) / 2;
            group_states(matches, 3) = (L_a + U_a) / 2;
        end
    end

    [uniq_group_states,~,tags] = unique(group_states,'rows');
    data_states(:, 3:5) = group_states;

    % In order to Plot S-A grid Map for all segment groups
    figure1 = figure('OuterPosition', [130, 50, 1062, 708]);
    axes1 = axes('Parent', figure1);
    hold(axes1, 'on');
    scatter(data_states(:, 1), data_states(:, 2), 'MarkerFaceColor', 'b', 'MarkerEdgeColor', 'b', ...
        'DisplayName', 'S-A Grid Values and States', 'MarkerFaceAlpha', 0.3, ...
        'MarkerFaceColor', [0 1 1]);
    xline(v_steps, 'HandleVisibility', 'off');
    yline(a_steps, 'HandleVisibility', 'off');
    state_texts = string(uniq_group_states(:, 1));
    text(uniq_group_states(:, 2), uniq_group_states(:, 3), state_texts, 'FontWeight', 'bold', 'FontSize', 12, ...
        'FontName', 'Times New Roman', 'Color', [0.635 0.0784 0.1843]);
    xlim(axes1, [speed_lower_bound speed_upper_bound - v_res]);
    ylim(axes1, [acc_lower_bound acc_upper_bound - a_res]);
    title(['The S-A Grid Map for Segment Group-', num2str(seg)], 'FontSize', 14);
    xlabel('Speed (km/h)', 'FontSize', 12);
    ylabel('Acceleration (m/s^2)', 'FontSize', 12);
    % saveas(gcf, ['SA_seg_', num2str(seg), '.fig']); % For saving plot

    % Calculate transition probability matrix
    tagged_dataset = data_states(:, 1:3);
    current_state = tagged_dataset(1:end - 1, 3); % Current states
    next_state = tagged_dataset(2:end, 3); % Next states
    state_transitions = [current_state, next_state];

    % State Transition matrix that gives the number of transitions between states
    state_trans_matrix = accumarray([current_state, next_state], 1);

    % State Transition Probability matrix that gives the probability of transitions between states
    trans_prob_matrix = state_trans_matrix ./ sum(state_trans_matrix, 2);

    cycle_duration = ref_seg_lengths(seg); % Segment duration (same as reference segment)
    gen_states = zeros(1, cycle_duration); % Initialize variable for Generated states
    first_states=zeros(num_segments, MCT); % Initialize variable for First states
    % Generate new segments using Monte Carlo experiments to maintain
    % the stochastic nature of a Markov chain
    for mcti = 1:MCT % Monte Carlo loop

        % Determine initial state for each segment
        if seg == 1 % First segment starts with zero speed and acceleration
            [~, index] = min(abs(data_states(:, 1) - 0) + abs(data_states(:, 2) - 0));
            first_states(seg, mcti) = data_states(index, 3);
        else
            % Subsequent segments start with initial states closest to
            % the final speed and acceleration of the previous segment
            [~, index] = min(abs(data_states(:, 1) - last_speed(seg - 1, mcti)));
            first_states(seg, mcti) = data_states(index, 3);
        end

        % Generate driving segment
        gen_states(1) = first_states(seg, mcti);

        for i = 2:cycle_duration % State transitions
            cumsum_probs = cumsum(trans_prob_matrix(gen_states(i - 1), :));
            gen_states(i) = find(rand <= cumsum_probs, 1);
        end

        uniq_gen_states = unique(gen_states, 'stable');
        state_values = cell(1, length(uniq_gen_states));
        state_values{1} = find(data_states(:, 3) == gen_states(1));
        constructed_driving_segment = zeros(cycle_duration, 2); % Constructed driving segment

        for i = 2:length(uniq_gen_states)
            state_values{i} = find(data_states(:, 3) == uniq_gen_states(i));
        end

        for i = 1:cycle_duration
            index_in_data_states = state_values{find(uniq_gen_states == gen_states(i))}; % Real data according to generated states

            if length(index_in_data_states) == 1
                rand_State = index_in_data_states; % If it's a single value
            else
                rand_State = randsample(index_in_data_states, 1); % If it's multiple values, choose randomly
            end

            constructed_driving_segment(i, :) = data_states(rand_State, 1:2);
        end

        % In the first segment, the initial speed and acceleration start with 0
        if seg == 1
            constructed_driving_segment(1, :) = [0, 0];
        end

        mct_cons_dc_speed{seg, mcti} = constructed_driving_segment;

        % Inter-segment memory unit
        last_speed(seg, mcti) = constructed_driving_segment(end, 1);
    end
end


% Compute DTW distance between reference and generated segments
dist_to_mcti = zeros(num_segments, MCT);
for seg = 1:num_segments
    y = all_segments{seg, ref_seg(seg)}(:, 1); % Reference segments
    for mcti = 1:MCT
        x = mct_cons_dc_speed{seg, mcti}(:, 1); % Generated segments
        dist_to_mcti(mcti,seg) = dtw(x, y);
    end
end

% To select the best segment from the segments generated by Monte Carlo 
% simulations, get the ones with the smallest DTW distance
[M,I] = min(dist_to_mcti);

best_seg_from_MCT=cell(num_segments,1);
for seg=1:num_segments
    best_seg_from_MCT(seg,1)=mct_cons_dc_speed(seg,I(seg));
end

const_cycle=cell2mat(best_seg_from_MCT);
% Calculate acceleration of the constructed Driving Cycle
for i=1:length(const_cycle)-1
    const_cycle(i,2)= (const_cycle(i+1,1)-const_cycle(i,1))/3.6;
end

% Plot Constructed DC
figure1=figure('OuterPosition',[130,50,1062,708]);
axes1 = axes('Parent', figure1);
hold(axes1, 'on');
plot(const_cycle(:, 1));
xlabel('Time (s)', 'FontSize', 14);
ylabel('Speed (km/h)', 'FontSize', 14);
title('Constructed Driving Cycles', 'FontSize', 14);
ylim(axes1, [0 max(const_cycle(:, 1)) + 10]);
segmentLimits = cumsum(ref_seg_lengths);
for i = 1:length(segmentLimits)
    xline(segmentLimits(i), 'r--', 'LineWidth', 1.5);
    text(segmentLimits(i) - ref_seg_lengths(i) / 2, max(const_cycle(:, 1)) + 5, ...
        ['Segment ', num2str(i)], 'HorizontalAlignment', 'center', ...
        'FontSize', 12, 'Color', [0.635, 0.0784, 0.1843], 'Rotation', 45);
end

% Concatenate reference segments
comref_seg=cell(num_segments,1);
for seg=1:num_segments
    comref_seg(seg,1)=all_segments(seg, ref_seg(seg));
end
comref_segments=cell2mat(comref_seg);

% Calculate the DTW distance between the constructed and
% concatenated reference segments
dist_cons_ref = dtw(const_cycle(:, 1), comref_segments(:, 1));