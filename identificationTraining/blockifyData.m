function blockifyData( soundsDir, className, niState )

disp( 'blockifying data' );

[~, soundFileNames] = makeSoundLists( soundsDir, className );

blockDataHash = getBlockDataHash( niState );
for i = 1:length( soundFileNames )
    
    fprintf( '.' );
    
    blocksSaveName = [soundFileNames{i} '.' blockDataHash '.blocks.mat'];
    if exist( blocksSaveName, 'file' ); continue; end;

    wp2SaveName = [soundFileNames{i} '.' getWp2dataHash( niState ) '.wp2.mat'];
    ls = load( wp2SaveName, 'wp2data' );
    wp2data = ls.wp2data;
    
    wp2BlockFeatures = [];
    
    for j = 1:size( wp2data, 1 )
        
        fprintf( '.' );
        
        nHops = size( wp2data(j).data, 2 );
        bs = getBlockSizes( niState );
        nHopsMinusLastBlock = max( nHops - bs.hopsPerBlock, 0 );
        for blockIdx = 1:(1 + ceil( nHopsMinusLastBlock / bs.hopsPerShift ) )
            
            blockstart = 1 + (blockIdx - 1) * bs.hopsPerShift;
            blockend = min( blockstart + bs.hopsPerBlock - 1, nHops );
            if (blockend - blockstart + 1) < bs.hopsPerBlock
                blockstart = nHopsMinusLastBlock + 1;
            end
            block = wp2data(j);
            block.data = block.data(:,blockstart:blockend,:);
            block.startTime = (blockstart - 1) * niState.wp2dataCreation.hopSizeSec;
            block.endTime = (blockend - 1) * niState.wp2dataCreation.hopSizeSec + niState.wp2dataCreation.winSizeSec;
            
            wp2BlockFeatures = [wp2BlockFeatures block];
        end
    end
    
    fprintf( '.' );
    save( blocksSaveName, 'wp2BlockFeatures', 'niState' );
    
end

disp( ';' );
