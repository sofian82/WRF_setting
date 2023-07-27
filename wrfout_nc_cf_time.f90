program wrfout_nc_cf 
  use netcdf
  implicit none

  integer :: statll, statlb

  ! This will be the netCDF ID for the file and data variable.
  integer :: varidrainnc2, varidrainc2, varidrainsh2
  integer :: varidrainnc1, varidrainc1, varidrainsh1
  integer :: ncidll, ncidlb, varidlat, varidlon

  ! We are reading 2D data, a 6 x 12 grid. 
  integer, parameter :: NX = 885, NY = 441
!  integer, parameter :: NDIMS = 2
  real :: data_inrainnc2(NX, NY), data_inrainc2(NX, NY), data_inrainsh2(NX, NY)
  real :: data_inrainnc1(NX, NY), data_inrainc1(NX, NY), data_inrainsh1(NX, NY)
  real :: data_lat(NX, NY), data_lon(NX, NY)
  real :: data_rain2(NX, NY), data_rain1(NX, NY), data_diff(NX, NY)
  real :: lat1d(NY), lon1d(NX) 

  integer :: varidftime
  character (len = 19) :: ftime 

  ! read latitude & longitude first
  statll = nf90_open("wrfoutc01.nc", NF90_NOWRITE, ncidll)
  call check(statll)
  if(statll == nf90_noerr) then
  ! Get the varid of the data variable, based on its name.
          call check( nf90_inq_varid(ncidll, "XLAT", varidlat) )
          call check( nf90_inq_varid(ncidll, "XLONG", varidlon) )        
          call check( nf90_inq_varid(ncidll, "RAINNC", varidrainnc2) )
          call check( nf90_inq_varid(ncidll, "RAINC", varidrainc2) )
          call check( nf90_inq_varid(ncidll, "RAINSH", varidrainsh2) )
          call check( nf90_inq_varid(ncidll, "Times", varidftime) )
  ! Read the data.
          call check( nf90_get_var(ncidll, varidlat, data_lat) )
          call check( nf90_get_var(ncidll, varidlon, data_lon) )
          call check( nf90_get_var(ncidll, varidrainnc2, data_inrainnc2) )
          call check( nf90_get_var(ncidll, varidrainc2, data_inrainc2) )
          call check( nf90_get_var(ncidll, varidrainsh2, data_inrainsh2) )
          call check( nf90_get_var(ncidll, varidftime, ftime) )
          print *, ftime
  ! Close nc
          call check( nf90_close(ncidll) )
          call lat1d_conv(data_lat,lat1d)
          call lon1d_conv(data_lon,lon1d)
!          call lat1d_conv(data_lat,lat1d)
  end if
  
  statlb = nf90_open("wrfoutb01.nc", NF90_NOWRITE, ncidlb)
  call check(statlb)
  if(statlb == nf90_noerr) then
  ! Get the varid of the data variable, based on its name.
          call check( nf90_inq_varid(ncidlb, "RAINNC", varidrainnc1) )
          call check( nf90_inq_varid(ncidlb, "RAINC", varidrainc1) )
          call check( nf90_inq_varid(ncidlb, "RAINSH", varidrainsh1) )
  ! Read the data.
          call check( nf90_get_var(ncidlb, varidrainnc1, data_inrainnc1) )
          call check( nf90_get_var(ncidlb, varidrainc1, data_inrainc1) )
          call check( nf90_get_var(ncidlb, varidrainsh1, data_inrainsh1) )
          call check( nf90_close(ncidlb) )
  end if
 
  data_rain2 = data_inrainnc2 + data_inrainc2 + data_inrainsh2
  data_rain1 = data_inrainnc1 + data_inrainc1 + data_inrainsh1
  data_diff = data_rain2 - data_rain1

!  call writeout(lat1d,lon1d,data_tot*1.0,i)
  call writeout(lat1d,lon1d,ftime,data_diff)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
contains
  subroutine check(status)
    integer, intent (in) :: status

    if(status /= nf90_noerr) then
      print *, trim(nf90_strerror(status))
  !    stop "Stopped"
    end if
  end subroutine check
  subroutine lat1d_conv(lat2d,lat1d) 
        real, intent (in) :: lat2d(NX,NY)
        integer :: k
        real, intent (out) :: lat1d(NY)
        do k=1, NY
          lat1d(k) = lat2d(1,k)
        end do
        return
  end subroutine lat1d_conv
  subroutine lon1d_conv(lon2d,lon1d)
        real, intent (in) :: lon2d(NX,NY)
        integer :: k
        real, intent (out) :: lon1d(NX)
        do k=1, NX
          lon1d(k) = lon2d(k,1)
        end do
        return
  end subroutine lon1d_conv
  subroutine writeout(lat,lon,ftime,dataout)
    character (len = *), parameter :: OUTFILE ="precip_t"
    character (len = *), parameter :: FMT1 ="(A8,A3)"
    integer, parameter :: NDIMS = 3
    real, intent (in) :: lat(NY), lon(NX) , dataout(NX,NY)
    character (len = 19), intent (in) :: ftime 
!    integer, intent (in) :: dataout(NX,NY)
    integer :: ncido
    character (len = 12) :: OUTFILENAME
    integer :: x_dimid, y_dimid, dimids(NDIMS)                                                
    integer :: varido, varidlato, varidlono
  !Attribute
    character (len = *), parameter :: UNITS = "units"
    character (len = *), parameter :: LAT_UNITS = "degrees_north"
    character (len = *), parameter :: LON_UNITS = "degrees_east"

    integer :: t_dimid, varidt
  
    character (len=31) :: timen
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    write(OUTFILENAME, FMT1), OUTFILE, ".nc"
!    write(OUTFILENAME, FMT1), OUTFILE, ".nc"
  ! Create the netCDF file. The nf90_clobber parameter tells netCDF to
  ! overwrite this file, if it already exists.
    call check( nf90_create(OUTFILENAME, NF90_CLOBBER, ncido) )
  ! Define the dimensions. NetCDF will hand back an ID for each. 
    call check( nf90_def_dim(ncido, "longitude", NX, x_dimid) )
    call check( nf90_def_dim(ncido, "latitude", NY, y_dimid) )
    call check( nf90_def_dim(ncido, "time", NF90_UNLIMITED, t_dimid) )
  ! The dimids array is used to pass the IDs of the dimensions of
  ! the variables. Note that in fortran arrays are stored in
  ! column-major format.
    dimids =  (/ x_dimid, y_dimid, t_dimid /)
  ! Define the variable. The type of the variable in this case is
  ! NF90_INT (4-byte integer).
    call check( nf90_def_var(ncido, "precipitation", NF90_FLOAT, dimids, varido) )
    call check( nf90_def_var(ncido, "latitude", NF90_FLOAT, y_dimid, varidlato) )
    call check( nf90_def_var(ncido, "longitude", NF90_FLOAT, x_dimid, varidlono) )
    call check( nf90_def_var(ncido, "time", NF90_INT, t_dimid, varidt) )
  ! Assign units attributes to coordinate var data. This attaches a
  ! text attribute to each of the coordinate variables, containing the
  ! units.
    call check( nf90_put_att(ncido, varidlato, UNITS, LAT_UNITS) )
    call check( nf90_put_att(ncido, varidlono, UNITS, LON_UNITS) )
    call check( nf90_put_att(ncido, varido, UNITS, "mm") )
    write(timen, '(A11,A10,A1,A8)'), 'days since ', ftime(1:10), ' ', ftime(12:)
    print *, timen
    call check( nf90_put_att(ncido, varidt, UNITS, timen) )
  ! End define mode. This tells netCDF we are done defining metadata.
    call check( nf90_enddef(ncido) )
  ! Write the pretend data to the file. Although netCDF supports
  ! reading and writing subsets of data, in this case we write all the
  ! data in one operation.
    call check( nf90_put_var(ncido, varido, dataout) )
    call check( nf90_put_var(ncido, varidlato, lat) )
    call check( nf90_put_var(ncido, varidlono, lon) )
    call check( nf90_put_var(ncido, varidt, 0) )
  ! Close the file. This frees up any internal netCDF resources
  ! associated with the file, and flushes any buffers.
    call check( nf90_close(ncido) )
  end subroutine writeout
end program wrfout_nc_cf 
