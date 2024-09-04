// https://code.earthengine.google.com/3701defe497560154820daa2408b8731

// This code will run the Parks et al. script for CBI calculations on any set of polygons provided in a shapefile
// Note that this Parks et al. script is designed for the Western United States; thus, polygons will be filtered
// to only include polygons in the Western US
// Fire polygons must have the burn year as an attribute (enter the name of attribute in "Inputs")

// Tyler L. McIntosh, Earth Lab, 2024

//  Code adapted from:
//            Parks SA, Holsinger LM, Koontz MJ, Collins, Whitman E, et al. 2019. Giving ecological meaning to satellite-derived 
//            fire severity metrics across North American forests within Google Earth Engine. Remote Sensing 2019, 11.
//            Original code link: https://code.earthengine.google.com/b4fb68fb7f8f883595dbe165ff82e0d9
//            Updated (2022) code link from Sean Parks: https://code.earthengine.google.com/484e28e8707a2b6031bea2de35272daa

//This code takes into account varied fire seasons:
//From Parks et al 2019 - AZ & NM have special seasons compared to the rest of the western US

var states = ee.FeatureCollection("TIGER/2018/States");

/////////////////////////////////////////////////////////////////////////////////////
//                        INPUTS                                                   //
/////////////////////////////////////////////////////////////////////////////////////
//--------------------       FIRE PERIMETER INPUT       ---------------------------//
// Import shapefile with fire polygons. The shapefile must have an attribute with the fire year
// Note that this script currently assumes that your polygon set has sequential years from startYear to endYear (see below parameters)
//       NAME           DESCRIPTION
//       any      year of fire

var firesRaw = ee.FeatureCollection("users/tymc5571/goodfire_dataset_for_analysis_2010_2020");
var startYear = 2010; //this is the earliest fire year in the dataset
var endYear = 2020; //this is the latest fire year in the dataset

// var firesRaw = ee.FeatureCollection("users/tymc5571/goodfire_dataset_for_analysis_1990_2020");
// var startYear = 1990; //this is the earliest fire year in the dataset
// var endYear = 2020; //this is the latest fire year in the dataset


var fireYearAttribute = 'Fire_Year'; //this is the name of the attribute that holds the fire year, if using fire year
var datasetName = 'good_fire'; //this is the name of the dataset you are putting in; it will be appended to your output file names
var outFolderName = 'GEE_Exports'; //this is the name of the folder in your GDrive where you want results exported
var selectedCRS = "EPSG:4326"; //this is the CRS that the data will be exported in


//----------        IMAGERY SELECTION        ---------------------------//
// Select the imagery to export from the suite of available indices below.  
// Add the VARIABLE NAMES (as desired) to brackets below, using quotes, e.g.  ['CBI', 'CBI_bc', 'dnbr', 'rbr']

//    VARIABLE NAME     DESCRIPTION
//    CBI               Composite Burn Index
//    CBI_bc            Bias-corrected Composite Burn Index
//    dnbr              delta normalized burn ratio
//    rbr               relativized burn ratio
//    rdnbr             relativized delta normalized burn ratio
///   dndvi             delta normalized differenced vegetation index
//    devi              delta enhanced vegetation index 
//    dndmi             delta normalized difference moisture index
//    dmirbi            delta mid-infrared bi-spectral index
//    post_nbr          post-fire normalized burn ratio
//    post_mirbi        post-fire mid-infrared bi-spectral index
var bandsToExport      = ['CBI_bc'];

/////////////////////////////////////////////////////////////////////////////////////
//                        END  OF INPUTS                                           //
/////////////////////////////////////////////////////////////////////////////////////



// //----------- Setup for the analysis ------------------//

print("Here is a sample of your input fire polygons: ", firesRaw.limit(10));

//----------- Filter to Western US ------------------//
var studyAreaWest = states.filter(ee.Filter.inList('NAME',['Washington','Oregon','California','Idaho','Montana','Nevada','Colorado','Wyoming','New Mexico','Arizona', 'Utah']));
var fires = firesRaw.filterBounds(studyAreaWest.geometry());

var outputRegion = studyAreaWest; //this is the region for which rasters will be exported


//----------- Get all fire years represented in filtered set ------------------//

var uniqueYears = ee.List.sequence(startYear, endYear).map(function(year){
 return ee.Number(year).format().slice(0, -2);  
});
var nYears = ee.Number(uniqueYears.length());

print('You have stated that your polygon set includes fires from', nYears, 'years. Those years are: ', uniqueYears);



////////////////////////////////////////////////////////////////////////////////////
//----------------  RANDOM FOREST SPECIFICATIONS---------------------//
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

////////////////////////////////////////////////////////////////////////////////////
//--------------------     PROCESSING     ----------------------------//
//-------- Initialize variables for fire perimeters  -----------------//
// create list with fire IDs  
// var fireID    = ee.List(fires.aggregate_array('Fire_ID')).getInfo();
// var nFires = fireID.length;

//  Suite of spectral indices available for export.  
var bandList      = ['dnbr', 'rbr', 'rdnbr', 'dndvi', 'devi', 'dndmi', 'dmirbi', 'post_nbr', 'post_mirbi', 'CBI', 'CBI_bc'];

//////////////////////////////////
//  GET LANDSAT COLLECTIONS      
//////////////////////////////////
// Landsat 5, 7, 8 and 9 Surface Reflectance (Level 2) Tier 1 Collection 2 
var ls9SR = ee.ImageCollection('LANDSAT/LC09/C02/T1_L2'),
    ls8SR = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2'),
    ls7SR = ee.ImageCollection('LANDSAT/LE07/C02/T1_L2'),
    ls5SR = ee.ImageCollection('LANDSAT/LT05/C02/T1_L2'),
    ls4SR = ee.ImageCollection('LANDSAT/LT04/C02/T1_L2');
  

print('LS Projection', ls9SR.first().projection());


/////////////////////////////////////////
// FUNCTIONS TO CREATE SPECTRAL INDICES
/////////////////////////////////////////
// Apply scaling factors.
var applyScaleFactors=function(lsImage) {
  var opticalBands=lsImage.select(["SR_B."]).multiply(0.0000275).add(-0.2);
  return lsImage.addBands(opticalBands, null, true);
};

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
};

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

// ///////////////////////////////////////////////////////////////////////////////////////////////
// // ------------------ Create Spectral Imagery for a region -----------------//



//region is a feature, all others are strings
var specImagery = function(regionF, fireYear, startday, endday) {

  // create pre- and post-fire imagery
  fireYear = ee.Date.parse('YYYY', fireYear);
  startday = ee.Number.parse(startday);
  endday   = ee.Number.parse(endday);  
  var region = regionF.geometry().bounds();


  // Pre-Imagery
  var preFireYear = fireYear.advance(-1, 'year');  
  //    check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked  
  var preFireIndices  = ee.Algorithms.If(lsCol.filterBounds(region)
                          .filterDate(preFireYear, fireYear)
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(region)
                            .filterDate(preFireYear, fireYear)
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi'])
                          );

  //    if any pixels within fire have only one 'scene' or less, add additional year backward to fill in behind
  //    as above, check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked
  var preFireYear2 = fireYear.advance(-2, 'year');
  var preFireIndices2  = ee.Algorithms.If(lsCol.filterBounds(region)
                          .filterDate(preFireYear2, fireYear)
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(region)
                            .filterDate(preFireYear2, fireYear)
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['pre_nbr','pre_ndvi', 'pre_ndmi', 'pre_evi','pre_mirbi'])
                          );
                          
  var pre_filled=ee.Image(preFireIndices).unmask(preFireIndices2);
  
  // Post-Imagery
  var postFireYear = fireYear.advance(1, 'year');
  
  //    check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked
  var postFireIndices  = ee.Algorithms.If(lsCol.filterBounds(region)
                           .filterDate(postFireYear, fireYear.advance(2, 'year'))
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(region)
                            .filterDate(postFireYear, fireYear.advance(2, 'year'))
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['post_nbr','post_ndvi', 'post_ndmi', 'post_evi','post_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['post_nbr','post_ndvi', 'post_ndmi', 'post_evi','post_mirbi'])
                          );
  //    if any pixels within fire have only one 'scene' or less, add additional year forward to fill in behind
  //    as above, check if imagery is available for time window; if so, get means across pixels; otherwise, output imagery will be masked
  var postFireIndices2  = ee.Algorithms.If(lsCol.filterBounds(region)
                          .filterDate(postFireYear, fireYear.advance(3, 'year'))
                          .filter(ee.Filter.dayOfYear(startday, endday))
                          .size(),
                          lsCol.filterBounds(region)
                            .filterDate(postFireYear, fireYear.advance(3, 'year'))
                            .filter(ee.Filter.dayOfYear(startday, endday))
                            .mean()
                            .select([0,1,2,3,4], ['post_nbr','post_ndvi', 'post_ndmi', 'post_evi','post_mirbi']),
                          ee.Image.cat(ee.Image(),ee.Image(),ee.Image(),ee.Image(),ee.Image())
                            .rename(['post_nbr','post_ndvi', 'post_ndmi', 'post_evi','post_mirbi'])
                          );
  var post_filled = ee.Image(postFireIndices).unmask(postFireIndices2);                      
  var fireIndices = pre_filled.addBands(post_filled);

  // calculate dNBR  
  var burnIndices = fireIndices.expression(
              "(b('pre_nbr') - b('post_nbr')) * 1000")
              .rename('dnbr').toInt().addBands(fireIndices);

  // calculate RBR 
  var burnIndices2 = burnIndices.expression(
            "b('dnbr') / (b('pre_nbr') + 1.001)")
            .rename('rbr').toInt().addBands(burnIndices);
            
  // calculate RdNBR
   var burnIndices3 = burnIndices2.expression(
            "abs(b('pre_nbr')) < 0.001 ? 0.001" + 
            ": b('pre_nbr')")
            .abs().sqrt().rename('pre_nbr2').toFloat().addBands(burnIndices2);
  
  var burnIndices4 = burnIndices3.expression(
            "b('dnbr') / b('pre_nbr2')")
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

  var burnIndices11 = cbi_rf.addBands(burnIndices10);
  
   // Create bias corrected CBI   
   var bias_correct = function(bandName) {
      var cbi_lo = bandName.expression("((b('CBI') - 1.5) * 1.3)  + 1.5");
      var cbi_hi = bandName.expression("((b('CBI') - 1.5) * 1.175) + 1.5");
      var cbi_mg = bandName.where(bandName.lte(1.5),cbi_lo).where(bandName.gt(1.5),cbi_hi);
      return cbi_mg.where(cbi_mg.lt(0),0).where(cbi_mg.gt(3),3)
                  .multiply(Math.pow(10,2)).floor().divide(Math.pow(10,2)) // set precision to two decimal places
                  .rename('CBI_bc');
  };
  
  var validMask   = pre_filled.select('pre_nbr').add(10).add(post_filled.select('post_nbr')).add(10); // Adding 10 ensures resulting image doesn't have 0 values that would become masked in final output bands
  var mask = waterMask.updateMask(validMask);
  var burnIndices12 = bias_correct(burnIndices11.select('CBI')).addBands(burnIndices11);
  burnIndices12 = burnIndices12.select(bandList,bandList)
              .updateMask(mask)
              .clip(regionF);

  return(burnIndices12);
};



//Function to derive CBI over the entire western US for a given year
//fireYear as a string
var specImageryFullRegion = function(fireYear) {
  
  var studyAreaNormalGrow = states.filter(ee.Filter.inList('NAME',['Washington','Oregon','California','Idaho','Montana','Nevada','Colorado','Wyoming', 'Utah']));
  var studyAreaSpecialGrow = states.filter(ee.Filter.inList('NAME',['New Mexico','Arizona'])); // these states have different growing seasons per Parks et al. 2019
  var startDayNormal = ee.String('152'); // start of growing season (julian day)
  var endDayNormal = ee.String('258'); // end of growing season (julian day)
  var startDaySpecial = ee.String('91');
  var endDaySpecial = ee.String('181');
  
  //run function for both normal and special growing regions
  var normalGrow = specImagery(studyAreaNormalGrow, fireYear, startDayNormal, endDayNormal);
  var specialGrow = specImagery(studyAreaSpecialGrow, fireYear, startDaySpecial, endDaySpecial);

  var combinedYear = ee.ImageCollection([normalGrow, specialGrow]).mosaic();
  combinedYear = combinedYear.set({
    'Fire_Year': fireYear
  });

  return(combinedYear);
};



// //Use the input polygons as masks on the regional calculations after reducing to image
// var data = uniqueYears.map(function(thisYear) {
//   var yearFires = fires.filter(ee.Filter.eq(fireYearAttribute, ee.Number.parse(thisYear)));
//   var regionData = specImageryFullRegion(thisYear);
//   var fireMask = yearFires.reduceToImage({
//     properties: [fireYearAttribute],
//     reducer:ee.Reducer.count()
//   }).gt(0);

//   var maskedData = regionData.updateMask(fireMask);

//   return(maskedData);
// });



//var paletteclass = ["#0000CD","#6B8E23", "#FFFF00","#FFA500","#FF0000" ]; 

//Map.addLayer(ee.Image(data.get(0)).select('CBI'),    {min:0, max:3, palette:paletteclass}, 'CBI');


// ///////////////////////////////////////////////////////////////////////////////////////////////
// // ----------------------   Export CBI and Other Spectral Imagery      ----------------------//
// var nBands = bandsToExport.length;
// nYears = endYear - startYear + 1;

// for (var j = 0; j < nYears; j++){
//   var year   = uniqueYears.get(j).getInfo();
//   var yearData = ee.Image(data.get(j));

//   for (var i = 0; i < nBands; i++) {
//     var bandExport = bandsToExport[i];  
//     var exportImg = yearData.select(bandExport);
//     Export.image.toAsset({
//       image: exportImg.toFloat(),  //casting to float maintains NA values in masked pixels
//       description: datasetName + '_' + year + '_' + bandExport,
//       assetId: datasetName + '_' + year + '_' + bandExport,
//       scale: 30,
//       crs: selectedCRS,
//       region: outputRegion,
//       maxPixels: 1e13
//   }); 
// }}






//Use the input polygons as masks on the regional calculations after reducing to image
var data2 = uniqueYears.map(function(thisYear) {
  var yearFires = fires.filter(ee.Filter.eq(fireYearAttribute, ee.Number.parse(thisYear)));
  var regionData = specImageryFullRegion(thisYear);
  var fireMask = yearFires.reduceToImage({
    properties: [fireYearAttribute],
    reducer:ee.Reducer.count()
  }).gt(0);

  var maskedData = regionData.updateMask(fireMask);

  return(maskedData.select('CBI_bc'));
});

print(uniqueYears);
var prependYear = function(year) {
  return ee.String('year_').cat(year);
};
var uniqueYearNames = uniqueYears.map(prependYear);
print(uniqueYearNames);

var fullColl = ee.ImageCollection(data2).toBands().rename(uniqueYearNames);

Export.image.toAsset({
    image: fullColl.toFloat(),  //casting to float maintains NA values in masked pixels
    description: 'goodFire_all_cbi_bc' + '_' + startYear + '_' + endYear,
    assetId: 'goodFire_all_cbi_bc' + '_' + startYear + '_' + endYear,
    scale: 30,
    crs: selectedCRS,
    region: outputRegion,
    maxPixels: 1e13
}); 




//////////
// DONE //
//////////
