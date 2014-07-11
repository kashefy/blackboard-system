classdef AcousticCuesKS < AbstractKS
    % ACOUSTICCUES
    
    properties (Access = public)
        dataObject;               % WP2 data object
    end
    
    methods
        function obj = AcousticCuesKS(blackboard, dataObject)
            obj = obj@AbstractKS(blackboard);
            obj.dataObject = dataObject;
        end
        
        function b = canExecute(obj)
            b = false;
            
            numPeripherySignals = obj.blackboard.getNumPeripherySignals;
            
            if numPeripherySignals == 0
                return
            else
                b = true;
            end
        end
        
        function execute(obj)
            if length(obj.blackboard.peripherySignals) < 1
                return
            else
                 wp2Periphery = obj.blackboard.peripherySignals{1};
%                 
%                 wp2Cues = process_WP2_cues(wp2Periphery.signals, ...
%                     obj.wp2States);
%                 wp2Features = process_WP2_features(wp2Cues, ...
%                     obj.wp2States);
%                 
%                 ic = wp2Cues(1).data;
%                 itds = wp2Cues(3).data .* 1000; % Convert ITD unit from s to ms
%                 ilds = wp2Cues(2).data;
%                 ratemap = wp2Cues(4).data;

                % Compute acoustic cues from WP2 data object
                ic = obj.dataObject.ic_xcorr{1}.Data;
                itds = obj.dataObject.itd_xcorr{1}.Data;
                ilds = obj.dataObject.ild{1}.Data;
                ratemap = obj.dataObject.ratemap_power{1}.Data;
                
                acousticCues = AcousticCues(wp2Periphery.blockNo, ...
                    wp2Periphery.headOrientation, itds, ilds, ic, ratemap );
                
                % Remove old acoustic cues from the bb
                if obj.blackboard.getNumAcousticCues > 0
                    obj.blackboard.removeAcousticCues();
                end
                
                % Add acoustic cues to the blackboard
                idx = obj.blackboard.addAcousticCues(acousticCues);
                
                if obj.blackboard.verbosity > 0
                    % Display that KS has fired
                    fprintf('-------- AcousticCuesKS has fired.\n');
                end
                
                % Trigger event
                notify(obj.blackboard, 'NewAcousticCues', BlackboardEventData(idx));
            end
        end
    end
end
