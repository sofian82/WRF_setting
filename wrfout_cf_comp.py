from netCDF4 import Dataset, date2num
from wrf import getvar, latlon_coords, destagger, interplevel
from datetime import datetime, timedelta

def getWRFVar(wrfout, var):
 nc = Dataset(wrfout)
 try:
  vari = getvar(nc, var)
 except ValueError:
  vari = getvar(nc, var.upper())
 lats, lons = latlon_coords(vari)
 return vari, lats, lons

def getWRFStagVar(wrfout, var):
 nc = Dataset(wrfout)
 try:
  vari = getvar(nc, var)
 except ValueError:
  vari = getvar(nc, var.upper())
 return vari #, lats, lons

def writeNet(ini,val,latis,longs,datau,datav,lev,fn):
 ds = Dataset(fn,'w',format='NETCDF4')
 timeDim = ds.createDimension('time', None)
 latDim = ds.createDimension('lat', len(latis))
 lonDim = ds.createDimension('lon', len(longs))
 ds.title = str(lev)+"hPa U & V wind from WRFOUT in CF compliance NETCDF"
 ds.subtitle = "WRFOUT domain 1km"
 ds.anything = "Any questions contact sofian@met.gov.my"
 time = ds.createVariable('time', 'f4', ('time',))
 lats = ds.createVariable('lat', 'f4', ('lat',))
 lons = ds.createVariable('lon', 'f4', ('lon',))
 uwind = ds.createVariable('U', 'f4', ('time', 'lat', 'lon',))
 vwind = ds.createVariable('V', 'f4', ('time', 'lat', 'lon',))
 time.units = 'hours since '+ini.strftime("%Y-%m-%d %H:00:00")
 lats.units = 'degrees_north'
 lons.units = 'degrees_east'
 uwind.units = 'm/s'
 vwind.units = 'm/s'
 uwind.standard_name = "850hPa U wind"
 vwind.standard_name = "850hPa V wind"
 time[:] = date2num(val, time.units)
 lats[:] = latis
 lons[:] = longs
 uwind[0,:,:] = datau
 vwind[0,:,:] = datav

def toNC(iniDate, forDate, wrfoutncL):
 var=['U', 'V']

#staggered coordinate
 u = getWRFStagVar(wrfoutncL, var[0]) 
 v = getWRFStagVar(wrfoutncL, var[1]) 
 latsU = getWRFStagVar(wrfoutncL, 'XLAT_U')
 lonsU = getWRFStagVar(wrfoutncL, 'XLONG_U')
 latsV = getWRFStagVar(wrfoutncL, 'XLAT_V')
 lonsV = getWRFStagVar(wrfoutncL, 'XLONG_V')

 uD = destagger(u, -1)
 latsUD = destagger(latsU, -1)
 lonsUD = destagger(lonsU, -1)
 vD = destagger(v, -2)
 latsVD = destagger(latsV, -2)
 lonsVD = destagger(lonsV, -2)
 
#normal coordinate. P : perturbation pressure
 p, latsP, lonsP = getWRFVar(wrfoutncL, 'P')
 pb, latsPB, lonsPB = getWRFVar(wrfoutncL, 'PB')
#pressure formula
 press = (p+pb)*0.01
#geopotential height formula
# (PH + PHB)/9.81 

#remove repetitive coordinate
 latit = latsP.data[:,0]
 longi = lonsP.data[0,:]

 hpa=[1000,850,700,500,200]

#forecast hour
 forH = (forDate-iniDate).days*24 + (forDate - iniDate).seconds//3600
# hpal=hpa[1]
 for hpal in hpa:
#interpolation to 850hpa
  uPresLev = interplevel(uD, press.data, hpal)
  vPresLev = interplevel(vD, press.data, hpal)

  fn = "W_"+"{:03d}".format(forH)+'_PM_wind_'+str(hpal)+'hpa.nc'
  writeNet(iniDate,forDate,latit,longi,uPresLev,vPresLev,hpal,fn)

if __name__ == '__main__':
#initial date
 tar = "2021-10-25_12"
 iniDate = datetime.strptime(tar,'%Y-%m-%d_%H')

#forecast date 
 fortar = "2021-10-31_12" 
 forDate = datetime.strptime(fortar,'%Y-%m-%d_%H')

#domain 
 domain='d03'

#wrfout name & location
 wrfoutDir = "./" 
 wrfoutncL = wrfoutDir+'wrfout_'+domain+'_'+forDate.strftime("%Y-%m-%d_%H")+'_00_00'
 
 toNC(iniDate, forDate, wrfoutncL)
