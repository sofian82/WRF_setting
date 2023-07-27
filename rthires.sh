#!/bin/sh

# Check if date (yyyy-mm-dd hh) is passed in.
# now="2017-10-24 18"

if [ $# -ge 2 ]; then
  now="$1 $2"
  hour=$2
else
  now=`date -u +%Y-%m-%d`
  hour=`date -u +%H`
  now="$now $hour"
fi

# Round hour to previous 6-hr increment.

diff=`expr $hour % 6`
now=`date -u -d "$now +$diff" "+%Y-%m-%d %H"`
date=`date -u -d "$now" +%y%j%H00`
hour=`date -u +%H -d "$now"`

bgmdl=gfs
if [ $# -eq 1 ]; then
  bgmdl=$1
fi
if [ $# -eq 3 ]; then
  bgmdl=$3
fi

if [ $bgmdl == "gfs" ]; then
  model=wrf
  mdlfcst=72
  bglvls=34
elif [ $bgmdl == "ukmo" ]; then
  model=wrf-$bgmdl
  if [ $hour -eq "06" ] || [ $hour -eq "18" ]; then
    mdlfcst=60
  else
    mdlfcst=72
  fi
  bglvls=71
else
  echo Unknown model type: $bgmdl
  exit 1
fi

home=~/mmd
root=$home/rtsys
wdir=$root/wrf
pdir=$root/post
idir=$root/image

mpirun=/gpfs/opt/intel/compilers_and_libraries/linux/mpi/intel64/bin/mpirun
pbs=/gpfs/software/altair/PBS/PBS_EXEC/default/bin

domain=mmd
res=333m

fcst=0
fcstinc=6
#fcstinc=3
maxfcst=$mdlfcst

bgdir=/mmdprod/data/grids/$bgmdl/grib2

# Set stack size to unlimited.

ulimit -s unlimited

# Set library path needed for netcdf shared libraries.

export LD_LIBRARY_PATH=/gpfs/usr/local/lib:/gpfs/opt/intel/lib/intel64

# Set model initial time to be either 00, 06, 12, 18 UTC.

lapsdate=`date -u -d "$now" +%Y-%m-%d_%H`
sdate=`date -u -d "$now" +%Y-%m-%d_%H:00:00`
syear=`date -u -d "$now" +%Y`
smonth=`date -u -d "$now" +%m`
sday=`date -u -d "$now" +%d`
shour=`date -u -d "$now" +%H`
mdldate=`date -u -d "$now" +%y%j%H00`
now=`date -u -d "$now $mdlfcst hours" "+%Y-%m-%d %H"`
edate=`date -u -d "$now" +%Y-%m-%d_%H:00:00`
eyear=`date -u -d "$now" +%Y`
emonth=`date -u -d "$now" +%m`
eday=`date -u -d "$now" +%d`
ehour=`date -u -d "$now" +%H`

# Create model run directory.
# Do all pre-processing in this directory.

mkdir -p /mmdprod/model/$domain/$res/$model/$mdldate
mkdir /mmdprod/model/$domain/$res/$model/$mdldate/refl
cd /mmdprod/model/$domain/$res/$model/$mdldate

# Start with a clean work space.

#rm -rf GRIBFILE.* FILE* Vtable METGRID.TBL metgrid.log.* met_em* rsl* namelist* *.log

# Create symbolic links to background grib files.

elapsed=0
freq_check=60
time_out=18000

for a2 in {A..Z}; do
for a3 in {A..Z}; do
  gribfile=GRIBFILE.A$a2$a3
  while [ ${#fcst} -lt 4 ]; do fcst="0$fcst"; done
  bgfile=$bgdir/$date$fcst
  if [ $bgmdl == "ukmo" ]; then
    bgfile=$bgfile".gz"
  fi
  while [ ! -e $bgfile ]; do
    if [ $elapsed -gt $time_out ]; then
      echo Missing model forecast grib file: $bgfile
      break
    fi
    sleep $freq_check
    elapsed=`expr $elapsed + $freq_check`
  done
  if [ -e $bgfile ]; then
    if [ $bgmdl == "ukmo" ]; then
      cp $bgfile $gribfile".gz"
      gunzip $gribfile
    else
      ln -fs $bgfile $gribfile
    fi
  else
    while [ ! -e $bgfile ]; do
      fcst=`expr $fcst + $fcstinc`
      while [ ${#fcst} -lt 4 ]; do fcst="0$fcst"; done
      bgfile=$bgdir/$date$fcst
      if [ $bgmdl == "ukmo" ]; then
        bgfile=$bgfile".gz"
      fi
      if [ $fcst -gt $maxfcst ]; then
        echo WRF script timed out while waiting for last model forecast grib file.
        exit 0
      fi
    done
    if [ $bgmdl == "ukmo" ]; then
      cp $bgfile $gribfile".gz"
      gunzip $gribfile
    else
      ln -fs $bgfile $gribfile
    fi
  fi
  fcst=`expr $fcst + $fcstinc`
  if [ $fcst -gt $maxfcst ]; then
    break 2
  fi
done
done

# Ungrib data into WRF intermediate data format.

rm -rf Vtable
if [ $bgmdl == "ukmo" ]; then
  ln -fs $wdir/src/WPS/ungrib/Variable_Tables/Vtable.UKMO_ENDGame Vtable
  ext=$domain-$res-ukmo
else
  ext=$domain-$res
  ln -fs $wdir/src/WPS/ungrib/Variable_Tables/Vtable.GFS Vtable
  geodir=$wdir/terrain/$domain-$res
fi
geodir=$wdir/terrain/$ext

cat $wdir/namelist/$ext/namelist.wps    \
  | sed s/start_date/"start_date = '$sdate', '$sdate',"/  \
  | sed s/end_date/"end_date   = '$sdate', '$sdate',"/    \
  | sed s?opt_output_from_geogrid_path?"opt_output_from_geogrid_path = '$geodir',"?  \
  | sed s/active_grid/"active_grid = .true.,.true.,"/  \
  > namelist.wps

$wdir/exe/ungrib.exe

# Horizontally interpolate intermediate data to WRF model grids.

ln -fs $wdir/src/WPS/metgrid/METGRID.TBL.ARW METGRID.TBL

cp ../static/host.list host.list
np=20
$mpirun -np $np -hostfile host.list $wdir/exe/metgrid.exe

# Set current link.

cd /mmdprod/model/$domain/$res/$model
rm -f current
ln -fs $mdldate current
cd current

# Vertically interpolate intermediate data to WRF model grid.

cat $wdir/namelist/$ext/namelist.input  \
  | sed s/run_hours/"run_hours   = 0,"/  \
  | sed s/start_year/"start_year  = $syear, $syear,"/  \
  | sed s/start_month/"start_month = $smonth, $smonth,"/  \
  | sed s/start_day/"start_day   = $sday, $sday,"/  \
  | sed s/start_hour/"start_hour  = $shour, $shour,"/  \
  | sed s/end_year/"end_year    = $syear, $syear,"/    \
  | sed s/end_month/"end_month   = $smonth, $smonth,"/    \
  | sed s/end_day/"end_day     = $sday, $sday,"/    \
  | sed s/end_hour/"end_hour    = $shour, $shour,"/    \
  | sed s/num_metgrid_levels/"num_metgrid_levels       = $bglvls,"/    \
  > namelist.input

# Start wrf-real followed by wrf-run.

cp /mmdprod/model/$domain/$res/$model/static/* .
$pbs/qsub real.pbs

# Run nestdown.

freq_check=10
donefile=realdone
while [ ! -e $donefile ]; do
  if [ $elapsed -gt $time_out ]; then
    echo real did not complete.
    break
  fi
  sleep $freq_check
  elapsed=`expr $elapsed + $freq_check`
done
sleep 1

freq_check=60
files=`ls /mmdprod/model/$domain/1km/$model/$mdldate/wrfout_d03* | wc -w`
while [ $files -le $mdlfcst ]; do
  if [ $elapsed -gt $time_out ]; then
    echo Not enough 1km WRF boundary files.
    break
  fi
  sleep $freq_check
  elapsed=`expr $elapsed + $freq_check`
  files=`ls /mmdprod/model/$domain/1km/$model/$mdldate/wrfout_d03* | wc -w`
done

files=`ls /mmdprod/model/$domain/1km/$model/$mdldate/wrfout_d03*`
for file in $files; do
  bdy=`echo $file | sed s/1km/333m/ | sed s/d03/d01/`
  ln -fs $file $bdy
done
mv wrfinput_d02 wrfndi_d02

cat $wdir/namelist/$ext/namelist.input  \
  | sed s/run_hours/"run_hours   = $mdlfcst,"/  \
  | sed s/start_year/"start_year  = $syear, $syear,"/  \
  | sed s/start_month/"start_month = $smonth, $smonth,"/  \
  | sed s/start_day/"start_day   = $sday, $sday,"/  \
  | sed s/start_hour/"start_hour  = $shour, $shour,"/  \
  | sed s/end_year/"end_year    = $eyear, $eyear,"/    \
  | sed s/end_month/"end_month   = $emonth, $emonth,"/    \
  | sed s/end_day/"end_day     = $eday, $eday,"/    \
  | sed s/end_hour/"end_hour    = $ehour, $ehour,"/    \
  | sed s/num_metgrid_levels/"num_metgrid_levels       = $bglvls,"/    \
  > namelist.input

$pbs/qsub ndown.pbs

# Run WRF.

freq_check=10
donefile=ndowndone
while [ ! -e $donefile ]; do
  if [ $elapsed -gt $time_out ]; then
    echo nestdown did not complete.
    break
  fi
  sleep $freq_check
  elapsed=`expr $elapsed + $freq_check`
done
sleep 1

rm -f wrfout_d01*
mv wrfinput_d02 wrfinput_d01
mv wrfbdy_d02 wrfbdy_d01

cat $wdir/namelist/$ext/namelist.input.hires  \
  | sed s/run_hours/"run_hours   = $mdlfcst,"/  \
  | sed s/start_year/"start_year  = $syear, $syear,"/  \
  | sed s/start_month/"start_month = $smonth, $smonth,"/  \
  | sed s/start_day/"start_day   = $sday, $sday,"/  \
  | sed s/start_hour/"start_hour  = $shour, $shour,"/  \
  | sed s/end_year/"end_year    = $eyear, $eyear,"/    \
  | sed s/end_month/"end_month   = $emonth, $emonth,"/    \
  | sed s/end_day/"end_day     = $eday, $eday,"/    \
  | sed s/end_hour/"end_hour    = $ehour, $ehour,"/    \
  | sed s/num_metgrid_levels/"num_metgrid_levels       = $bglvls,"/    \
  > namelist.input

$pbs/qsub wrf.pbs

# Start the model post-processing script.

$pdir/bin/mdlpost-hires.sh $domain $model > $home/log/hires-post.log 2>&1 &

# Clean-up.

#rm -rf GRIBFILE.* FILE* Vtable METGRID.TBL metgrid.log.*

exit 0
