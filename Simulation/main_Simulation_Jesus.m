% Main script for the synthetic simulations

% Simulated data for the Extrinsic Calibration of a 2D Lidar and a
% Monocular Camera based on Corner Structures without Pattern

% clear classes
clear;

% Main options:
main_sim_file = fullfile( pwd, 'main_Simulation.ini' );
mainOpts = readConfigFile( main_sim_file );
extractStructFields( mainOpts );
clear mainOpts

% Set Rig properties
rig_config_file = fullfile( pwd, 'rig.ini' );
rigOpts = readConfigFile( rig_config_file );
extractStructFields( rigOpts );
clear rigOpts
Rig = CSimRig( eye(3), zeros(3,1), R_c_s, t_c_s,... % Extrinsic options
               N, FOVd, scan_sd, d_range,... % Lidar options
               K, res, f, cam_sd ); % Camera options                

% trihedron = CTrihedron( LPattern );
% trihedron = CTrihedron( LPattern, eye(3), 3*[-1 -1 0]' );
trihedron = CTrihedron( LTrihedron, eye(3), 0*[0 0 1]' );
corner = CCorner( LCorner, expmap( [-1 +1 0], deg2rad(-45) ) );
checkerboard = CCheckerboard( LCheckerboard, RotationZ(deg2rad(45))*RotationY(deg2rad(45)) );
pattern = { trihedron, corner, checkerboard };

% Generate Rig (Camera) poses for different patterns
% Trihedron
gen_config_file = fullfile( pwd, 'pose_gen_trihedron.ini' );
[R_w_Cam_Trihedron, R_w_LRF_Trihedron, t_w_Rig_Trihedron, ~, ~] = generate_random_poses( Nobs, gen_config_file, Rig );

% Corner
gen_config_file = fullfile( pwd, 'pose_gen_corner.ini' );
[R_w_Cam_Corner, R_w_LRF_Corner, t_w_Rig_Corner, ~, ~] = generate_random_poses( Nobs, gen_config_file, Rig );

% Checkerboard
gen_config_file = fullfile( pwd, 'pose_gen_checkerboard.ini' );
[R_w_Cam_Checkerboard, R_w_LRF_Checkerboard, t_w_Rig_Checkerboard, ~, ~] = generate_random_poses( Nobs, gen_config_file, Rig );

tic
optim_config_file = fullfile( pwd, 'optim_config.ini' );
optimOpts = readConfigFile( optim_config_file );
extractStructFields( optimOpts );
clear optimOpts
triOptim = CTrihedronOptimization( K,...
    RANSAC_Rotation_threshold,...
    RANSAC_Translation_threshold,...
    debug_level, maxIters,...
    minParamChange, minErrorChange);
cornerOptim = CCornerOptimization( K,...
    debug_level, maxIters,...
    minParamChange, minErrorChange);
checkerOptim = CCheckerboardOptimization( K,...
    debug_level, maxIters,...
    minParamChange, minErrorChange);

for i=1:Nobs
    % Correspondences for Kwak's algorithm
    if WITHCORNER
        % Update reference (LRF) pose in Rig for Corner
        Rig.updateLRFPose( R_w_LRF_Corner{i}, t_w_Rig_Corner{i} );
        corr_ = corner.getCorrespondence(Rig);
        cornerOptim.stackObservation( corr_ );
    end
    
    % Correspondences for Vasconcelos and Zhang's algorithm
    % Update reference (LRF) pose in Rig for Checkerboard
    Rig.updateLRFPose( R_w_LRF_Checkerboard{i}, t_w_Rig_Checkerboard{i} );
    co = checkerboard.getCorrespondence( Rig );
    checkerOptim.stackObservation( co );
%     check_corresp{1,i} = checkerboard.p2D;
%     check_corresp{2,i} = checkerboard.getProjection( Rig.Camera );    
%     check_corresp{3,i} = 1000 * cell2mat(checkerboard.getScan( Rig.Lidar ));
    
    % Correspondences for trihedron
    % Update reference (Camera) pose in Rig for Trihedron
    Rig.updateCamPose( R_w_Cam_Trihedron{i}, t_w_Rig_Trihedron{i} );
    co_ = trihedron.getCorrespondence( Rig );
    triOptim.stackObservation( co_ );
    
    if WITHPLOTSCENE
        % Need to update Rig poses for plotting
        figure
        subplot(131)
        Rig.updateCamPose( R_w_Cam_Trihedron{i}, t_w_Rig_Trihedron{i} );
        trihedron.plotScene(Rig.Camera, Rig.Lidar);
        subplot(132)
        Rig.updateLRFPose( R_w_LRF_Corner{i}, t_w_Rig_Corner{i} );
        corner.plotScene(Rig.Camera, Rig.Lidar);
        subplot(133)
        Rig.updateLRFPose( R_w_LRF_Checkerboard{i}, t_w_Rig_Checkerboard{i} );
        checkerboard.plotScene(Rig.Camera, Rig.Lidar);
        set(gcf,'units','normalized','position',[0 0 1 1]);
        keyboard
        close
    end
end

% ------------- Trihedron ----------------
% Set number of observations to use
triOptim.setNobs(Nobs);
if WITHTRIHEDRON
    triOptim.setInitialRotation( [ 0 -1  0
                                   0  0 -1
                                   1  0  0 ] ); % Updated in RANSAC
    if WITHRANSAC
        triOptim.filterRotationRANSAC;
    end
    if WITHVERBOSE
        triOptim.disp_N_R_inliers;
    end
    R_c_s_nw = triOptim.optimizeRotation_NonWeighted;
    R_c_s_dw = triOptim.optimizeRotation_DiagWeighted;
    R_c_s_w  = triOptim.optimizeRotation_Weighted;

    if WITHRANSAC
        triOptim.filterTranslationRANSAC( Rig.R_c_s ); % Should receive some estimated rotation
    end
    if WITHVERBOSE
    triOptim.disp_N_t_inliers;
    end
    R0_for_t = R_c_s_w;
    triOptim.setInitialTranslation( Rig.t_c_s + 0.05*randn(3,1) );
    t_3D_nw = triOptim.optimizeTranslation_3D_NonWeighted( R0_for_t );
    t_3D_w  = triOptim.optimizeTranslation_3D_Weighted( R0_for_t );
    t_2D_nw = triOptim.optimizeTranslation_2D_NonWeighted( R0_for_t );
    t_2D_w = triOptim.optimizeTranslation_2D_Weighted( R0_for_t );
    
    [R_global, t_global] = triOptim.optimizeGlobal_Ort_3D( R_c_s_w, t_3D_w );
    
end

% ------------- Kwak -------------------
cornerOptim.setNobs(Nobs);
if WITHCORNER
    if WITHVERBOSE
        cornerOptim.disp_N_obs;
    end
    % Generate random input (near GT)
    R_aux = Rig.R_c_s + randn(3,3)*0.08;
    [U,S,V] = svd(R_aux);
    Rt0 = [ U*V' , Rig.t_c_s + 0.05*randn(3,1) ];
    % Optimize
    cornerOptim.setInitialRotation( Rt0(1:3,1:3) );
    cornerOptim.setInitialTranslation( Rt0(1:3,4) );
    [R_k_nw, t_k_nw] = cornerOptim.optimizeRt_NonWeighted;
    % [R_k_w,  t_k_w]  = cornerOptim.optimizeRt_Weighted;
    [R_k_cw, t_k_cw] = cornerOptim.optimizeRt_ConstWeighted;
    % [R_k_pw, t_k_pw] = cornerOptim.optimizeRt_PreWeighted;
    [R_kC_nw, t_kC_nw] = cornerOptim.optimizeRt_C_NonWeighted;
end

% % ---------- Vasconcelos -------------------------
if WITHZHANG
    checkerOptim.setInitialRotation( Rig.R_c_s );
    checkerOptim.setInitialTranslation( Rig.t_c_s );
%     [T_planes,lidar_points] = checkerboard.getCalibPlanes( Rig, check_corresp );
%     [T, ~,~,~,~] = lccMinSol(T_planes,lidar_points);
%     [T_z, ~,~,~,~] = lccZhang(T_planes, lidar_points);
    [R_v,t_v] = checkerOptim.optimizeRt_Vasc;
    [R_z,t_z] = checkerOptim.optimizeRt_Zhang;
%     x_v = pose_inverse(T); x_v(1:3,4) = x_v(1:3,4)/1000;
%     x_z = pose_inverse(T_z); x_z(1:3,4) = x_z(1:3,4)/1000;
end

% Compute hessian in convergence points for different methods
if WITHTRIHEDRON
    H_R = triOptim.FHes_Orthogonality( R_c_s_w );
    H_t_3D = triOptim.FHes_3D_PlaneDistance( Rig.R_c_s, t_3D_w );
    H_t_2D = triOptim.FHes_2D_LineDistance( Rig.R_c_s, t_2D_w );
    H_Rt = triOptim.FHes_Global_Ort_3D( R_global, t_global );
end
if WITHCORNER
    H_Rt_k = cornerOptim.FHes_2D_LineDistance( [R_k_cw, t_k_cw] );
    H_Rt_kC = cornerOptim.FHes_C_2D_LineDistance( [R_k_cw, t_k_cw] );
end
if WITHPLOTHESSIAN
    figure
    f1 = 2; f2 = 4; index = 1;
    if WITHTRIHEDRON
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_R); m = min(eigv);
        title(sprintf('Tri:R:W\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_R ); shading interp;
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_t_3D); m = min(eigv);
        title(sprintf('Tri:t:3D:W\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_t_3D ); shading interp;
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_t_2D); m = min(eigv);
        title(sprintf('Tri:t:2D:W\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_t_2D ); shading interp;
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_Rt(1:3,1:3)); m = min(eigv);
        title(sprintf('Tri:Rt:Global:W\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_Rt(1:3,1:3) ); shading interp;
    end
    if WITHCORNER
        index = f2 + 1; % New row
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_Rt_k(1:3,1:3)); m = min(eigv);
        title(sprintf('Kwak:R:NW\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_Rt_k(1:3,1:3) ); shading interp;
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_Rt_k(4:6,4:6)); m = min(eigv);
        title(sprintf('Kwak:t:NW\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_Rt_k(4:6,4:6) ); shading interp;
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_Rt_kC(1:3,1:3)); m = min(eigv);
        title(sprintf('Kwak:R:C:NW\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_Rt_kC(1:3,1:3) ); shading interp;
        subplot(f1,f2,index), hold on, index = index + 1;
        eigv = eig(H_Rt_kC(4:6,4:6)); m = min(eigv);
        title(sprintf('Kwak:t:C:NW\n%i:%i:%i',round(eigv(1)/m),round(eigv(2)/m),round(eigv(3)/m)));
        plotcov3( zeros(3,1), H_Rt_kC(4:6,4:6) ); shading interp;
    end
end

% Plot cost functions near GT
if WITHPLOTCOST
    figure('Name','Trihedron Rotation: Orthogonality cost function');
    title('Trihedron Rotation: Orthogonality cost function');
    triOptim.plotRotationCostFunction( Rig.R_c_s );
    
    figure('Name','Trihedron Rotation: Global cost function');
    title('Trihedron Rotation: Global cost function');
    triOptim.plotRotation_Global_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    if WITHCORNER
        figure('Name','Corner Rotation: 2D distance cost function');
        title('Corner Rotation: 2D distance cost function');
        cornerOptim.plotRotationCostFunction( Rig.R_c_s, Rig.t_c_s );
        
        figure('Name','Corner Rotation: 2D distance cost function (only center)');
        title('Corner Rotation: 2D distance cost function (only center)');
        cornerOptim.plotRotation_C_CostFunction( Rig.R_c_s, Rig.t_c_s );
    end
    
    figure('Name','Trihedron Translation: 3D distance cost function');
    title('Trihedron Translation: 3D distance cost function');
    triOptim.plotTranslation_3D_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Trihedron Translation: 2D distance cost function');
    title('Trihedron Translation: 2D distance cost function');
    triOptim.plotTranslation_2D_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    figure('Name','Trihedron Translation: Global cost function');
    title('Trihedron Translation: Global cost function');
    triOptim.plotTranslation_Global_CostFunction( Rig.R_c_s, Rig.t_c_s );
    
    if WITHCORNER
        figure('Name','Corner Translation: 2D distance cost function');
        title('Corner Translation: 2D distance cost function');
        cornerOptim.plotTranslationCostFunction( Rig.R_c_s, Rig.t_c_s );
        
        figure('Name','Corner Translation: 2D distance cost function (only center)');
        title('Corner Translation: 2D distance cost function (only center)');
        cornerOptim.plotTranslation_C_CostFunction( Rig.R_c_s, Rig.t_c_s );
    end
end

% ---------- Display the errors -------------------------
if WITHVERBOSE
    fprintf('(*) -> best current method\n');
    
    if WITHTRIHEDRON
        fprintf('=============================================================\n');
        fprintf('Trihedron (non-weighted) rotation error (deg): \t \t %f \n',...
            angularDistance(R_c_s_nw,Rig.R_c_s) );
        fprintf('Trihedron (diag-weighted) rotation error (deg): \t %f \n',...
            angularDistance(R_c_s_dw,Rig.R_c_s) );
        fprintf('(*) Trihedron (weighted) rotation error (deg): \t \t %f \n',...
            angularDistance(R_c_s_w,Rig.R_c_s) );
        fprintf('Trihedron (global W, 3D) rotation error (deg): \t \t %f \n',...
            angularDistance(R_global,Rig.R_c_s) );
        fprintf('=============================================================\n');
        fprintf('Trihedron (non-weighted, 3D) translation error (cm): \t %f \n',...
            norm(t_3D_nw-Rig.t_c_s)*100 );
        fprintf('Trihedron (    weighted, 3D) translation error (cm): \t %f \n',...
            norm(t_3D_w-Rig.t_c_s)*100 );
        fprintf('Trihedron (non-weighted, 2D) translation error (cm): \t %f \n',...
            norm(t_2D_nw-Rig.t_c_s)*100 );
        fprintf('Trihedron (    weighted, 2D) translation error (cm): \t %f \n',...
            norm(t_2D_w-Rig.t_c_s)*100 );
        fprintf('Trihedron (    global W, 3D) translation error (cm): \t %f \n',...
            norm(t_global-Rig.t_c_s)*100 );
    end
    
    if WITHCORNER
        fprintf('=============================================================\n');
        fprintf('=============================================================\n');
        % fprintf('    Kwak (      weighted) rotation error (deg): \t %f \n',   angularDistance(R_k_w, Rig.R_c_s) );
        fprintf('    Kwak (  non-weighted) rotation error (deg): \t %f \n',   angularDistance(R_k_nw,Rig.R_c_s ));
        fprintf('(*) Kwak (const-weighted) rotation error (deg): \t %f \n',   angularDistance(R_k_cw,Rig.R_c_s ));
        fprintf('    Kwak-C (  non-weighted) rotation error (deg): \t %f \n',   angularDistance(R_kC_nw,Rig.R_c_s ));
        fprintf('=============================================================\n');
        % fprintf('    Kwak (      weighted) translation error (cm): \t %f \n', 100*norm(t_k_w  - Rig.t_c_s) );
        fprintf('    Kwak (  non-weighted) translation error (cm): \t %f \n', 100*norm(t_k_nw - Rig.t_c_s) );
        fprintf('(*) Kwak (const-weighted) translation error (cm): \t %f \n', 100*norm(t_k_cw - Rig.t_c_s) );
        fprintf('    Kwak-C (  non-weighted) translation error (cm): \t %f \n', 100*norm(t_kC_nw - Rig.t_c_s) );
    end
    
    if WITHZHANG
        fprintf('=============================================================\n');
        fprintf('=============================================================\n');
        fprintf('Vasconcelos rotation error (deg): \t\t\t %f \n', angularDistance(R_v,Rig.R_c_s) );
        fprintf('Zhang rotation error (deg): \t\t\t\t %f \n', angularDistance(R_z,Rig.R_c_s) );
        fprintf('=============================================================\n');
        fprintf('Vasconcelos translation error (cm): \t\t\t %f \n', 100 * norm(t_v - Rig.t_c_s) );
        fprintf('Zhang translation error (cm): \t\t\t\t %f \n', 100 * norm(t_z - Rig.t_c_s) );
    end
    toc
end