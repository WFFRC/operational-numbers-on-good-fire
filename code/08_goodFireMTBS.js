// This script inputs a list of MTBS polygons and calculates low/mod vs. high severity fire for forested pixels. Severity (CBI) is derived from Parks et al.2019 method.
// https://code.earthengine.google.com/?scriptPath=users%2Frudplatt%2FGoodFire%3AgoodFireMTBS

// A few notes:
// • The perFireExport task runs the task and reducers for every single polygon individually, and then exports a summary CSV for each event.  This approach runs into memory limitations if you are working with a large number of complex polygons. In that case, you need to either (1) increase the scale, or (2) divide the input polygons into smaller chunks, run the process for each chunk, and combine the CSVs at the end.
// • The CBIMTBS task runs the task and reducers simultaneously for all features in a featureCollection.  The output is an image rather than a CSV.  To get per-event outputs in a CSV, you need another step: run a spatial reducer of the single image using the featureCollection.  This is much more memory efficient than the perFIreExport task.  The down side: does not deal with overlapping polygons. To work around this, you can run the task for shorter time spans (e.g. fires within single calendar years don’t overlap much).  Then run the spatial reducer for each year-image.  


var MTBS = ee.FeatureCollection("USFS/GTAC/MTBS/burned_area_boundaries/v1"),
    cbiViz = {"opacity":1,"bands":["CBI_bc"],"min":0,"max":3,"palette":["ff3925","4eff74"]},
    states = ee.FeatureCollection("TIGER/2016/States"),
    sevMosaic = ee.ImageCollection("USFS/GTAC/MTBS/annual_burn_severity_mosaics/v1"),
    frg = ee.ImageCollection("LANDFIRE/Fire/FRG/v1_2_0"),
    lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8"),
    forVis = {"opacity":1,"bands":["Land_Cover"],"palette":["09a91d"]},
    chunks = ee.FeatureCollection("projects/ee-rudplatt-test/assets/fires2010_2021_er3"),
    cbiExpVis = {"opacity":1,"bands":["CBImask_max"],"min":-0.22400744889387214,"max":2.834613509499932,"palette":["48ff0c","ff3110"]},
    cbiRcsVis = {"opacity":1,"bands":["constant"],"min":1,"palette":["2b27ff","fcff1f","ff1818"]};

//----------- Settings for the analysis ------------------//
var studyArea = states.filter(ee.Filter.inList('NAME',['Washington','Oregon','California','Idaho','Montana','Nevada','Utah','Colorado','Wyoming']))
//var studyArea = states.filter(ee.Filter.inList('NAME',['New Mexico','Arizona']))
var fires = MTBS.filter(ee.Filter.bounds(studyArea)).filter(ee.Filter.notEquals('Incid_Type','Prescribed Fire'))

// add the year as a property
var fires = fires.map(function(boundary) {
  var yr = ee.Date(boundary.get('Ig_Date')).format('YYYY')
  return boundary.set({year: yr}).copyProperties(boundary)
});

// filter by year if needed
var fires = fires.filter(ee.Filter.eq('year','2021'))

// other settings
var TS = 16 // set tilescale for reduceRegion, output will take longer when higher
var SC = 30 // set cell size for reducers
var startday = ee.Number(152) // start of growing season (julian day)
var endday = ee.Number(258) // end of growing season (julian day)
// For most of the west use 152-258
// For Arizona, New Mexico ecoregions use 91-181

print(fires,'fires')

//-----------  Calculate indices for combined Landsat ImageCollection ------------------//
// Bands for the random forest classification
var rf_bands = ['def', 'lat',  'rbr', 'dmirbi', 'dndvi', 'post_mirbi'];

//Load training data for Random Forest classification
var cbi = ee.FeatureCollection("users/grumpyunclesean/CBI_predictions/data_for_ee_model");

//Load climatic water deficit variable (def) for random forest classification
var def = ee.Image("users/grumpyunclesean/CBI_predictions/def").rename('def').toInt();

//Create latitude image for random forest classification
var lat = ee.Image.pixelLonLat().select('latitude').rename('lat').round().toInt();

// Parameters for random forest classification
var nrow_training_fold = cbi.size();    // number of training observations 
var minLeafPopulation  = nrow_training_fold.divide(75).divide(6).round();

// Random forest classifier
var fsev_classifier = ee.Classifier.smileRandomForest(
    {numberOfTrees: 500, 
    minLeafPopulation: minLeafPopulation, 
    seed: 123
    }) 
  .train(cbi, 'CBI', rf_bands)
  .setOutputMode('REGRESSION'); 

//////////////////////////////////
//  GET LANDSAT COLLECTIONS      
//////////////////////////////////
// Landsat 5, 7, 8 and 9 Surface Reflectance (Level 2) Tier 1 Collection 2 
var ls9SR = ee.ImageCollection('LANDSAT/LC09/C02/T1_L2'),
    ls8SR = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2'),
    ls7SR = ee.ImageCollection('LANDSAT/LE07/C02/T1_L2'),
    ls5SR = ee.ImageCollection('LANDSAT/LT05/C02/T1_L2'),
    ls4SR = ee.ImageCollection('LANDSAT/LT04/C02/T1_L2');
    
/////////////////////////////////////////
// FUNCTIONS TO CREATE SPECTRAL INDICES
/////////////////////////////////////////
// Apply scaling factors.
var applyScaleFactors=function(lsImage) {
  var opticalBands=lsImage.select(["SR_B."]).multiply(0.0000275).add(-0.2);
  return lsImage.addBands(opticalBands, null, true)
}

// Returns vegetation indices for LS8 and LS9
var ls8_9_Indices = function(lsImage){
  var nbr  = lsImage.normalizedDifference(['SR_B5', 'SR_B7']).toFloat();
  var ndvi = lsImage.normalizedDifference(['SR_B5', 'SR_B4']).toFloat();
  var ndmi = lsImage.normalizedDifference(['SR_B5', 'SR_B6']).toFloat();
  var evi  = lsImage.expression(
              '2.5 * ((SR_B5 - SR_B4) / (SR_B5 + 6 * SR_B4 - 7.5 * SR_B2 + 1))',
              {'SR_B5': lsImage.select('SR_B5'),
              'SR_B4': lsImage.select('SR_B4'),
              'SR_B2': lsImage.select('SR_B2')}).toFloat();
  var mirbi = lsImage.expression(
              '((10 * SR_B6) - (9.8 * SR_B7) + 2)',
              {'SR_B6': lsImage.select('SR_B6'),
               'SR_B7': lsImage.select('SR_B7'),
              }).toFloat();              
  var qa = lsImage.select(['QA_PIXEL']);
  return nbr.addBands([ndvi,ndmi,evi,mirbi,qa])
          .select([0,1,2,3,4,5], ['nbr','ndvi','ndmi','evi','mirbi','QA_PIXEL'])
          .copyProperties(lsImage, ['system:time_start']);
          
  };

// Returns indices for LS4, LS5 and LS7
var ls4_7_Indices = function(lsImage){
  var nbr  = lsImage.normalizedDifference(['SR_B4', 'SR_B7']).toFloat();
  var ndvi = lsImage.normalizedDifference(['SR_B4', 'SR_B3']).toFloat();  
  var ndmi = lsImage.normalizedDifference(['SR_B4', 'SR_B5']).toFloat();
  var evi = lsImage.expression(
              '2.5 * ((SR_B4 - SR_B3) / (SR_B4 + 6 * SR_B3 - 7.5 * SR_B1 + 1))',
              {'SR_B4': lsImage.select('SR_B4'),
               'SR_B3': lsImage.select('SR_B3'),
               'SR_B1': lsImage.select('SR_B1')}).toFloat();
  var mirbi = lsImage.expression(
              '((10 * SR_B5) - (9.8 * SR_B7) + 2)',
              {'SR_B5': lsImage.select('SR_B5'),
               'SR_B7': lsImage.select('SR_B7'),
              }).toFloat();              
  var qa = lsImage.select(['QA_PIXEL']);
  return nbr.addBands([ndvi,ndmi,evi,mirbi,qa])
          .select([0,1,2,3,4,5], ['nbr','ndvi','ndmi','evi','mirbi','QA_PIXEL'])
          .copyProperties(lsImage, ['system:time_start']);
  };

/////////////////////////////////////////////////
// FUNCTION TO MASK CLOUD, WATER, SNOW, ETC.
////////////////////////////////////////////////
var lsCfmask = function(lsImage) {
	// Bits 3,4,5,7: cloud,cloud-shadow,snow,water respectively.
	var cloudsBitMask      = (1 << 3);
	var cloudShadowBitMask = (1 << 4);
	var snowBitMask        = (1 << 5);
	var waterBitMask       = (1 << 7);
	// Get the pixel QA band.
	var qa = lsImage.select('QA_PIXEL');
	// Flags should be set to zero, indicating clear conditions.
  var clear =  qa.bitwiseAnd(cloudsBitMask).eq(0)
              .and(qa.bitwiseAnd(cloudShadowBitMask).eq(0))
              .and(qa.bitwiseAnd(snowBitMask).eq(0))
              .and(qa.bitwiseAnd(waterBitMask).eq(0));
	return lsImage.updateMask(clear).select([0,1,2,3,4]) 
              .copyProperties(lsImage,["system:time_start"]);
}

// Create water mask from Hansen's Global Forest Change to use in processing function
var waterMask = ee.Image('UMD/hansen/global_forest_change_2015').select(['datamask']).eq(1);

/////////////////////////////////////////////////
// RUN FUNCTIONS ON LANDSAT COLLECTION
////////////////////////////////////////////////
var ls9 = ls9SR.map(applyScaleFactors)
                .map(ls8_9_Indices)
                .map(lsCfmask);
var ls8 = ls8SR.map(applyScaleFactors)
               .map(ls8_9_Indices)
               .map(lsCfmask);
var ls7 = ls7SR.map(applyScaleFactors)
               .map(ls4_7_Indices)
               .map(lsCfmask);
var ls5 = ls5SR.map(applyScaleFactors)
               .map(ls4_7_Indices)
               .map(lsCfmask);
var ls4 = ls4SR.map(applyScaleFactors)
               .map(ls4_7_Indices)
               .map(lsCfmask);
                
// Merge Landsat Collections
var lsCol = ee.ImageCollection(ls9.merge(ls8).merge(ls7).merge(ls5).merge(ls4));

// --------- Calculate Spectral Indices for each fire and combine with static data -----------------//
var indices = ee.ImageCollection(fires.map(function(ft){
  // use 'Event_ID' as unique identifier
  var fName    = ft.get("Event_ID");
  
  // select fire
  var fire = ft;
  var fireBounds = ft.geometry().bounds()
  
  var fireYear = ee.Date(ee.Date(fire.get('Ig_Date')).format('YYYY'))

  // Pre-Imagery
  var preFireYear = fireYear.advance(-1, 'year');  
  //    check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked  
  var preFireIndices  = ee.Algorithms.If(lsCol.filterBounds(fireBounds)
                          .filterDate(preFireYear, fireYear)
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(fireBounds)
                            .filterDate(preFireYear, fireYear)
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi'])
                          )

  //    if any pixels within fire have only one 'scene' or less, add additional year backward to fill in behind
  //    as above, check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked
  var preFireYear2 = fireYear.advance(-2, 'year');
  var preFireIndices2  = ee.Algorithms.If(lsCol.filterBounds(fireBounds)
                          .filterDate(preFireYear2, fireYear)
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(fireBounds)
                            .filterDate(preFireYear2, fireYear)
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi'])
                          )
                          
  var pre_filled=ee.Image(preFireIndices).unmask(preFireIndices2);
  
  // Post-Imagery
  var postFireYear = fireYear.advance(1, 'year');
  //    check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked
  var postFireIndices  = ee.Algorithms.If(lsCol.filterBounds(fireBounds)
                           .filterDate(postFireYear, fireYear.advance(2, 'year'))
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(fireBounds)
                            .filterDate(postFireYear, fireYear.advance(2, 'year'))
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['post_nbr','post_ndvi', 'post_ndmi', 'post_evi','post_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi'])
                          )
  //    if any pixels within fire have only one 'scene' or less, add additional year forward to fill in behind
  //    as above, check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked
  var postFireIndices2  = ee.Algorithms.If(lsCol.filterBounds(fireBounds)
                          .filterDate(postFireYear, fireYear.advance(3, 'year'))
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(fireBounds)
                            .filterDate(postFireYear, fireYear.advance(3, 'year'))
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['post_nbr','post_ndvi', 'post_ndmi', 'post_evi','post_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi'])
                          ) 
  var post_filled = ee.Image(postFireIndices).unmask(postFireIndices2)                        
  var fireIndices = pre_filled.addBands(post_filled);

  // calculate dNBR  
  var burnIndices = fireIndices.expression(
              "(b('pre_nbr') - b('post_nbr')) * 1000")
              .rename('dnbr').toInt().addBands(fireIndices);

  // calculate RBR 
  var burnIndices2 = burnIndices.expression(
            "b('dnbr') / (b('pre_nbr') + 1.001)")
            .rename('rbr').toInt().addBands(burnIndices);

  var burnIndices3 = burnIndices2.select('pre_nbr').abs().rename('pre_nbr2').addBands(burnIndices2); // this is my new way of calculating
  
  var burnIndices4 = burnIndices3.expression(
            "b('dnbr') / sqrt(b('pre_nbr2'))")           
            .rename('rdnbr').toInt().addBands(burnIndices3);
          
  // calculate dNDVI
  var burnIndices5 = burnIndices4.expression(
              "(b('pre_ndvi') - b('post_ndvi')) * 1000")
              .rename('dndvi').toInt().addBands(burnIndices4);
              
  // calculate dEVI
  var burnIndices6 = burnIndices5.expression(
              "(b('pre_evi') - b('post_evi')) * 1000")       
              .rename('devi').toInt().addBands(burnIndices5);

   // calculate dNDMI  
  var burnIndices7 = burnIndices6.expression(
              "(b('pre_ndmi') - b('post_ndmi')) * 1000")                  
              .rename('dndmi').toInt().addBands(burnIndices6);
              
   // calculate dMIRBI   
  var burnIndices8 = burnIndices7.expression(
              "(b('pre_mirbi') - b('post_mirbi')) * 1000")             
              .rename('dmirbi').toInt().addBands(burnIndices7);
              
  // Multiply post_mirbi band by 1000 to put it on the same scale as CBI plot extractions
  var post_mirbi_1000 = burnIndices8.select("post_mirbi").multiply(1000).toInt();
  burnIndices8 = burnIndices8.addBands(post_mirbi_1000, null, true); // null to copy all bands; true to overwrite original post_mirbi
  
 //  add in climatic water deficit variable, i.e. def
 var burnIndices9 = burnIndices8.addBands(def);
 
  //  add in latitude 
 var burnIndices10 = burnIndices9.addBands(lat);

 // Classify the image with the same bands used to train the Random Forest classifier.
  var cbi_rf = burnIndices10.select(rf_bands).classify(fsev_classifier).
            rename('CBI').toFloat()
            .multiply(Math.pow(10,2)).floor().divide(Math.pow(10,2));  // set precision to two decimal places

  var burnIndices11 = cbi_rf.addBands(burnIndices10).clip(fire)
  
   // Create bias corrected CBI   
   var bias_correct = function(bandName) {
      var cbi_lo = bandName.expression("((b('CBI') - 1.5) * 1.3)  + 1.5");
      var cbi_hi = bandName.expression("((b('CBI') - 1.5) * 1.175) + 1.5");
      var cbi_mg = bandName.where(bandName.lte(1.5),cbi_lo).where(bandName.gt(1.5),cbi_hi);
      return cbi_mg.where(cbi_mg.lt(0),0).where(cbi_mg.gt(3),3)
                  .multiply(Math.pow(10,2)).floor().divide(Math.pow(10,2)) // set precision to two decimal places
                  .rename('CBI_bc');
  };
  
  var burnIndices12 = bias_correct(burnIndices11.select('CBI')).addBands(burnIndices11);
  var validMask = pre_filled.select('pre_nbr').add(10).add(post_filled.select('post_nbr')).add(10) // Adding 10 ensures resulting image doesn't have 0 values that would become masked in final output bands
  
  // Get fire severity images
  var CBIbc = ee.Image(burnIndices12.select('CBI_bc'));
  
  // find no data areas
  var noData = CBIbc.gte(0).selfMask().rename('noData')

  // Reclass FRC data to low/mixed (1) vs. replacement (2) vs. masked (3)
  var frcCONUS = frg.filterMetadata('system:index','contains','CONUS').first()
  var frcRcl = frcCONUS.remap([1,2,3,4,5,111,112,131,132,133],[1,2,1,2,2,3,3,3,3,3],0,'FRG').rename('frcRcls');
  var frcLowMix = frcRcl.eq(1).rename('frcLowMix')
  var frcReplace = frcRcl.eq(2).rename('frcReplace')

  // Find 1 year before the fire
  var preFireYear = fireYear.advance(-1, 'year');  

  // Get forest cover info for the year before the fire
  var lcmsFire = lcms
    .filter(ee.Filter.and(
      ee.Filter.date(preFireYear, fireYear),
      ee.Filter.eq('study_area', 'CONUS')
    ))
    .first().select('Land_Cover');
  var lcmsFireRcl = lcmsFire.remap([1,4,8,10,3,7,5,9,11,12,13,14,15],[1,2,2,2,2,2,3,3,3,4,4,4,5],0,'Land_Cover').rename('Land_Cover');
  var lcmsFor = lcmsFireRcl.eq(1).rename('lcmsFor')

  // Define fire thresholds and mask by forest year before fire
  var CBImask = CBIbc.updateMask(lcmsFor).rename('CBImask')
  var CBIlowmod =  CBImask.lt(2.25).and(CBImask.gte(0.1)).rename('CBIlowmod'); // define refugia as bias corrected CBI less than this threshold (.1, .68, 1.25)
  var CBIunburned = CBImask.lt(0.1).rename('CBIunburned'); // define refugia as bias corrected CBI less than this threshold (.1, .68, 1.25)
  var CBIhighsev= CBImask.gte(2.25).rename('CBIhighsev'); // define refugia as bias corrected CBI less than this threshold (.1, .68, 1.25)
  
  //find low sev forest part of low/mixed FRC class
  var frcLowCbiLow = CBIlowmod.updateMask(frcLowMix).rename('frcLowCbiLow')
  var frcReplaceCbiHigh = CBIhighsev.updateMask(frcReplace).rename('frcReplaceCbiHigh')
  var frcLowCbiHigh = CBIhighsev.updateMask(frcLowMix).rename('frcLowCbiHigh')
  var frcReplaceCbiLow = CBIlowmod.updateMask(frcReplace).rename('frcReplaceCbiLow')
  var frcLowCbiUnb = CBIunburned.updateMask(frcLowMix).rename('frcLowCbiUnb')
  var frcReplaceCbiUnb = CBIunburned.updateMask(frcReplace).rename('frcReplaceCbiUnb')

  var burnIndices13 = burnIndices12
    .addBands(CBImask)
    .addBands(CBIunburned.multiply(ee.Image.pixelArea()))
    .addBands(CBIhighsev.multiply(ee.Image.pixelArea()))
    .addBands(CBIlowmod.multiply(ee.Image.pixelArea()))
    .addBands(lcmsFor.multiply(ee.Image.pixelArea()))
    .addBands(frcLowMix.multiply(ee.Image.pixelArea()))
    .addBands(frcLowCbiLow.multiply(ee.Image.pixelArea()))
    .addBands(frcReplaceCbiHigh.multiply(ee.Image.pixelArea()))
    .addBands(frcLowCbiHigh.multiply(ee.Image.pixelArea()))
    .addBands(frcReplaceCbiLow.multiply(ee.Image.pixelArea()))
    .addBands(frcLowCbiUnb.multiply(ee.Image.pixelArea()))
    .addBands(frcReplaceCbiUnb.multiply(ee.Image.pixelArea()))
    .addBands(noData.multiply(ee.Image.pixelArea()))
    .addBands(ee.Image.pixelArea().rename('areaHA'))

  return burnIndices13.set({
                        'fireID' : ft.get('Event_ID'),
                        'fireYear' : ft.get('year'),
  }); 
}));

print(indices,'indices')

// ------------ summarize data within polygons ------- //
function perimSummary(fireperim) {
  var fireInfo = indices.filterMetadata('fireID', 'equals', fireperim.get('Event_ID')).first();
  
  // define reducers
  var reducers = ee.Reducer.mean().combine({
    reducer2: ee.Reducer.max(),
    sharedInputs: true
  }).combine({
  reducer2: ee.Reducer.sum(),
  sharedInputs: true
  }).combine({
  reducer2: ee.Reducer.count(),
  sharedInputs: true
  })
  
  // define geometry and simplify a little
  var geom = fireperim.geometry().simplify({'maxError': 100})//.buffer(-100);
  
  // Summarize data within fire perimeter (forests only)
  var summary = fireInfo.reduceRegion({
      reducer: reducers,
      geometry: geom,
      scale: SC,
      maxPixels: 1e13,
      tileScale: TS
  })

  // add properties to the featurecollection for later export

  fireperim = fireperim.set('CBIhighsev', ee.Number(summary.get('CBIhighsev_sum')).multiply(0.001).round().divide(10)) 
  fireperim = fireperim.set('CBIunburned', ee.Number(summary.get('CBIunburned_sum')).multiply(0.001).round().divide(10))
  fireperim = fireperim.set('CBIlowmodsev', ee.Number(summary.get('CBIlowmod_sum')).multiply(0.001).round().divide(10))
  
  fireperim = fireperim.set('frcLowCbiLow', ee.Number(summary.get('frcLowCbiLow_sum')).multiply(0.001).round().divide(10))
  fireperim = fireperim.set('frcReplaceCbiHigh', ee.Number(summary.get('frcReplaceCbiHigh_sum')).multiply(0.001).round().divide(10))
  fireperim = fireperim.set('frcLowCbiHigh', ee.Number(summary.get('frcLowCbiHigh_sum')).multiply(0.001).round().divide(10))
  fireperim = fireperim.set('frcReplaceCbiLow', ee.Number(summary.get('frcReplaceCbiLow_sum')).multiply(0.001).round().divide(10))

  fireperim = fireperim.set('frcLowCbiUnb', ee.Number(summary.get('frcLowCbiUnb_sum')).multiply(0.001).round().divide(10))
  fireperim = fireperim.set('frcReplaceCbiUnb', ee.Number(summary.get('frcReplaceCbiUnb_sum')).multiply(0.001).round().divide(10))

  fireperim = fireperim.set('preFireFor', ee.Number(summary.get('lcmsFor_sum')).multiply(0.001).round().divide(10)) 
  fireperim = fireperim.set('areaHA', ee.Number(summary.get('areaHA_sum')).multiply(0.001).round().divide(10)) 

  return fireperim
}

// ---------------------- Compute, visualize, export ----------------------//
var firesummary = fires.map(perimSummary);

// get LCMS forest layer just for visualization
var lcms2021 = lcms.filterDate('2020', '2021')  // range: [1985, 2022]
               .filter('study_area == "CONUS"')  // or "SEAK"
               .first()
               .select('Land_Cover')
               .eq(1)

var sevVis = {
  bands: ['Severity'],
  min: 0,
  max: 6,
  palette:
      ['000000', '006400', '7fffd4', 'ffff00', 'ff0000', '7fff00', 'ffffff']
};

Map.addLayer(sevMosaic, sevVis, 'Severity', false);
Map.addLayer(fires, {color: 'gray', fillColor: '00000000'}, "Fire perimeters");
//Map.addLayer(indices.select('frcLowCbiLow').first().gt(0).selfMask(),{min:0, max:1, palette:['yellow','orange']}, 'Good Fire, FRG low/mixed',false);
//Map.addLayer(indices.select('CBIlowmod').first().gt(0).selfMask(),{min:0, max:1, palette:['yellow','orange']}, 'Good Fire, all FRG');
//Map.addLayer(indices.select('CBIhighsev').first().gt(0).selfMask(),{min:0, max:1, palette:['yellow','red']}, 'High Severity Fire, all FRG');
//Map.addLayer(lcms2021.selfMask(),forVis,'LCMS Forest 2021',false)
//Map.addLayer(indices.first().select('CBI_bc'),cbiViz,"CBI",false)
//Map.addLayer(indices.select('frcLowMix').first().gt(0).selfMask(),{min:0, max:1, palette:['yellow','red']}, 'FRC Low Mixed', false);

// Create CBI and severity class images for visualization and export
var cbiExport = indices.select('CBImask').reduce(ee.Reducer.max()).selfMask()

var sevReclass = ee.Image(0)
    .where(cbiExport.lt(0.1), 1) //unburned
    .where(cbiExport.gte(0.1).and(cbiExport.lt(2.25)), 2) //low and mod
    .where(cbiExport.gte(2.25), 3) // high severity
    .selfMask()

Map.addLayer(cbiExport,cbiExpVis,"CBI Export")
Map.addLayer(sevReclass,cbiRcsVis,"Sev reclass")

Export.image.toAsset({
  image: cbiExport,
  description: 'cbiMTBS_',
  scale: 30,
  maxPixels: 3784216672400
});

Export.image.toAsset({
  image: sevReclass,
  description: 'sevClassExport_',
  scale: 30,
  maxPixels: 3784216672400
});

// Export the FeatureCollection
var exported = firesummary.select(['.*'], null, false)//.sort('pct_refugia',false); // sort pct_refugia ascending to ensure that all columns are exported
Export.table.toDrive({
  collection: exported,
  description: 'perFireExport_',
  fileFormat: 'CSV'
});
