    PROGRAM DDFIELD
! --------------------------------- v6 ----------------------------
      USE DDPRECISION,ONLY : WP
      IMPLICIT NONE

      CHARACTER :: CFLPOL*80

      INTEGER*2,ALLOCATABLE :: ICOMP(:,:)

      INTEGER ::                                       &
         IANISO,JA,JAT,JD,JPT,JPY,JPYM,JPZ,JPZM,       &
         JX,JXMAX,JXMIN,JY,JYMAX,JYMIN,JZ,JZMAX,JZMIN, &
         MXNAT,MODE,NAB,NAT0,NPT,NTHREADS,NX,NY,NZ

      INTEGER,ALLOCATABLE :: IXYZ0(:,:)

      REAL(WP) ::                                           &
         AKD2,GAMMA,GAMMAKD4,CWORD,DSTORAGE,DXPHYS,         &
         FAC,KD,KDR,MB,                                     &
         PHASYZ,PHASY,PHASY1,PHASZ1,PI,PYD,PYDDX,PZD,PZDDX, &
         R,R2,R4,RANGE,RANGE2,RJPY,RWORD,STORAGE,STORAGE0,  &
         WAVE,X0,X2,X2Y2,XA,XB,XMAX,XMAXPHYS,XMIN,XMINPHYS, &
         Y0,YA,YB,YMAX,YMAXPHYS,YMIN,YMINPHYS,              &
         Z0,ZA,ZB,ZMAX,ZMAXPHYS,ZMIN,ZMINPHYS

      REAL(WP) :: &
         AKD(3),  &
         DR(3),   &
         DX(3),   &
         RHAT(3), &
         X(3),    &
         XX0(3)
 
      REAL(WP),ALLOCATABLE :: &
         BETADF(:),           &
         PHIDF(:),            &
         THETADF(:)

      COMPLEX(WP) :: CXFAC,CXFACB,CXFACR,CXI,CXPDOT,CXTRM

      COMPLEX(WP) :: &
         CXB(3),     &
         CXB0(3),    &
         CXE(3),     &
         CXE0(3),    &
         CXP(3)

      COMPLEX(WP),ALLOCATABLE :: &
         CXADIA(:,:),            &
         CXAOFF(:,:),            &
         CXPOL(:,:),             &
         DCXB(:,:),              &
         DCXE(:,:)

      INTEGER OMP_GET_NUM_THREADS

      !ADDED BY NWB 2_28_12 FOR FAST-e E-FIELD
      REAL(WP) :: Center(3)
      REAL(WP) :: c, e_charge, EFieldConstant, omega, gamma_tmp, k_mag, DS
      REAL(WP) :: BesselArg, DielectricConst, velocity
      REAL(WP) :: Radius
      REAL(WP) :: besselk1, besselk0

      !*** Constants for fast electron
      c = 3.E8_WP             !Speed of light
      e_charge = 1._WP        !Charge of electron
      velocity = 0.5_WP * c   !Speed of electron
      DielectricConst = 1._WP !Dielectric constant

      !*** E-beam center
      Center(1) =  0.0_WP
      Center(2) =  0.0_WP
      Center(3) =  0.0_WP

      DATA CXI/(0._WP,1._WP)/

!=======================================================================
!                          DDField
!
! Program DDfield takes the target polarization array output by DDSCAT,
! and calculates the electric field at arbitrary locations inside or
! outside the target.
!
! Input: file DDfield.in with list of coordinates, given as
!        x/dx(1), y/dx(2), z/dx(3)
!
!        where dx(j)=lattice spacing in direction j
!        with dx(1)*dx(2)*dx(3)=d**3
!
! Method: the electromagnetic field is calculated to be the sum of
!         the incident EM field plus the EM field generated by each 
!         dipole, and each replica dipole, with inclusion of all
!         retardation effects.
!         The EM field produced by each dipole is calculated exactly 
!         EXCEPT for the contribution of any dipole less than 1 
!         lattice spacing d away [there can be as many as 8 such
!         dipoles].
!         In case of dipoles at distance < d, the electric and
!         magnetic field contributions are suppressed by a factor
!         (r/d)^4
!         With this factor, it is found that E field remains quite
!         uniform within a uniformly polarized target, and the
!         field as one approaches each dipole site is then calculated 
!         correctly as the field due to all other dipoles.
!
!         Note: present method is adapted to compute the EM field
!         within and just outside the target.  If at large distances
!         from the target, exp(-(gamma*k*r)^4) suppression factor
!         for replica dipole contribution needs to be modified so as
!         to be small over the Fresnel zone.  This can be done by
!         suitable reduction in gamma.
! history:
! 06.09.14 (BTD) first written
! 06.09.21 (BTD) generalized to treat periodic targets
! 06.09.22 (BTD) now write out PYD,PZD to output files
! 06.10.25 (BTD) modified DDfield to use same cutoff factor
!                exp(-beta*(k*r)^4) as used by ESELF
! 07.01.21 (BTD) added output to screen giving JXMIN,JXMAX,JYMIN,JYMAX,
!                JZMIN,JZMAX
! 07.01.26 (BTD) cosmetic changes to output
!                added comments
! 07.06.21 (BTD) modify to use pol output from DDSCAT v7.0.2
!                with XX0(1-3)=location in TF of lattice site (0,0,0)
! 08.01.17 (BTD) * added IANISO to argument list of READPOL
!                * added ICOMP,BETADF,THETADF,PHIDF to READPOL argument list
!                * add MODE to argument list of READPOL
!                * modified to first call READPOL with MODE=0 to determine
!                  size of stored file; then allocate necessary memory;
!                  then call READPOL with MODE=1 to read stored
!                  polarization data.
!                * modified to write out useful information concerning
!                  target geometry
! 08.03.23 (BTD) * changed from exp(-beta*(kr)^4) to
!                  exp(-(alpha*kr)^4)
!                  read alpha from ddfield.in
! 08.04.20 (BTD) * changed notation: ALPHA -> GAMMA
!                * correction: had been mistakenly calculating suppression 
!                  factor as exp[-(gamma^2*(kr)^4)]
!                  correct this to exp[-(gamma*kr)^4]
! 08.05.21 (BTD) v7.0.6
!                * corrected typo:
!                  PHASZ1=AKD(3)*PYDDX -> PHASZ1=AKD(3)*PZDDX
! 08.08.24 (BTD) v7.0.7 release
!                v3
!                * added openmp directives for parallelization
!                * to support openmp, changed DCXB(JD) -> DCXB(JD,JA)
!                * to optimize memory access, changed 
!                  DCXE(JA,JD) -> DCXE(JD,JA)
!                * added xmin,xmax,ymin,ymax,zmin,zmax to output field 
!                  ddfield.E and ddfield.B
! 08.08.26 (BTD) * moved DX(1) into parallel region so that each thread
!                  will know DX(1)
! 08.08.27 (BTD) * changed power-law from (r/d)^{4.5} to (r/d)^4
!                  in factor suppressing contribution of dipoles within
!                  distance d.  This choice was based on comparison of
!                  field along track1 and track2 for an infinite slab
!                  with m=1.5+0.02i, h/lambda=0.2, illuminated by light
!                  with incidence angle theta_i=40deg (this is the case
!                  used as illustration in Draine & Flatau 2008)
! 08.08.29 (BTD) * added xmin/d, ... zmax/d and dphys to output
! 08.11.05 (BTD) * added missing "THEN" to statement
!                  IF(NPT.EQ.1)THEN
!                  error reported by Gouraya Gourmi-Said 
!                  (Laboratorie de Physique du Solide,
!                   Facult�s Universitaires Notre-Dame de la Paix,
!                   Namur, Belgium)
! 09.04.10 (BTD) v5 
!                * modified to keep spaces between output columns of 
!                  ddfield.E and ddfield.B even when one of the dipole 
!                  locations/d is smaller than -100, or one of the 
!                  E or B components is smaller than -10.
! 09.07.08 (BTD) v5 
!                * corrected typo reported by Shuzhou Li in evaluation 
!                  of XMIN and XMINPHYS (output describing spatial 
!                  extent of target)
! 10.02.04 (BTD) v6
!                * changed form of input file ddfield.in to allow
!                  user to simply specify endpoints of (x,y,z) track, 
!                  and number of points in track
! end history

! Copyright (C) 2006,2007,2008,2009,2010
!               B.T. Draine and P.J. Flatau
! This code is covered by the GNU General Public License.
!=======================================================================

      PI=4._WP*ATAN(1._WP)

#ifdef openmp
      WRITE(0,FMT='(A)')'compiled with OpenMP enabled'
#endif

! for storage computations:

      MB=REAL(1024**2)
      IF(WP==KIND(0.E0))THEN
         RWORD=4._WP
         CWORD=2._WP*RWORD
         STORAGE0=6.79
         WRITE(0,FMT='(A)')'compiled for single precision'
      ELSEIF(WP==KIND(0.D0))THEN
         RWORD=8._WP
         CWORD=2._WP*RWORD
         STORAGE0=6.794
         WRITE(0,FMT='(A)')'compiled for double precision'
      ELSE
         WRITE(0,*)'Fatal error in DDfield: unable to determine word length'
         STOP
      ENDIF
      STORAGE=STORAGE0


! Input control file:

      OPEN(UNIT=3,FILE='ddfield.in')

! Output files:

      OPEN(UNIT=7,FILE='ddfield.E')
      OPEN(UNIT=8,FILE='ddfield.B')

! Read name of file containing stored polarization information:

! Preliminary allocation

      MXNAT=1
      ALLOCATE(ICOMP(MXNAT,3))
      ALLOCATE(IXYZ0(MXNAT,3))
      ALLOCATE(BETADF(MXNAT))
      ALLOCATE(THETADF(MXNAT))
      ALLOCATE(PHIDF(MXNAT))
      ALLOCATE(CXADIA(MXNAT,3))
      ALLOCATE(CXAOFF(MXNAT,3))
      ALLOCATE(CXPOL(MXNAT,3))

      READ(3,*)CFLPOL
      READ(3,*)GAMMA
      IF(GAMMA>0.1_WP.OR.GAMMA<1.E-4_WP)THEN
         WRITE(0,FMT='(A,1PE10.3,A)')'GAMMA=',GAMMA,                &
                                     ' is unusual: is this intended?'
      ENDIF
!*** diagnostic
!      write(0,*)'ddfield ckpt 1: cflpol=',cflpol
!***
      MODE=0
      CALL READPOL(MODE,MXNAT,NX,NY,NZ,NAT0,IANISO,ICOMP,IXYZ0,PYD,PZD,AKD,   &
                   DX,XX0,WAVE,BETADF,THETADF,PHIDF,CXE0,CXADIA,CXAOFF,CXPOL, &
                   CFLPOL)

!*** diagnostic
!      write(0,*)'ddfield ckpt 2: returned from readpol with nat0=',nat0
!***
! Now allocate necessary storage:

      DEALLOCATE(ICOMP)
      DEALLOCATE(IXYZ0)
      DEALLOCATE(CXADIA)
      DEALLOCATE(CXAOFF)
      DEALLOCATE(CXPOL)

      MXNAT=NAT0
      STORAGE=STORAGE0

      DSTORAGE=REAL(2*3*MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6605)DSTORAGE,STORAGE
      ALLOCATE(ICOMP(MXNAT,3))

      DSTORAGE=REAL(4*3*MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6610)DSTORAGE,STORAGE
      ALLOCATE(IXYZ0(MXNAT,3))

      DSTORAGE=CWORD*REAL(3*MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6620)DSTORAGE,STORAGE
      ALLOCATE(CXADIA(MXNAT,3))

      DSTORAGE=CWORD*REAL(3*MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6630)DSTORAGE,STORAGE
      ALLOCATE(CXAOFF(MXNAT,3))

      DSTORAGE=CWORD*REAL(3*MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6640)DSTORAGE,STORAGE
      ALLOCATE(CXPOL(MXNAT,3))

      DEALLOCATE(BETADF)
      DEALLOCATE(THETADF)
      DEALLOCATE(PHIDF)

      DSTORAGE=RWORD*REAL(MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6660)DSTORAGE,STORAGE
      ALLOCATE(BETADF(MXNAT))

      DSTORAGE=RWORD*REAL(MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6660)DSTORAGE,STORAGE
      ALLOCATE(THETADF(MXNAT))

      DSTORAGE=RWORD*REAL(MXNAT)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6660)DSTORAGE,STORAGE
      ALLOCATE(PHIDF(MXNAT))

      MODE=1
      CALL READPOL(MODE,MXNAT,NX,NY,NZ,NAT0,IANISO,ICOMP,IXYZ0,PYD,PZD,AKD,   &
                   DX,XX0,WAVE,BETADF,THETADF,PHIDF,CXE0,CXADIA,CXAOFF,CXPOL, &
                   CFLPOL)

!*** diagnostic
!      write(0,*)'ddfield ckpt 3'
!      write(0,*)' ja  jx  jy  jz'
!      do j=1,nat0
!         write(0,9711)j,ixyz0(j,1),ixyz0(j,2),ixyz0(j,3)
!      enddo
! 9711 format(i3,3i4)
!      write(0,9712)xx0
! 9712 format('x0=',3f14.6)
!****

      DSTORAGE=CWORD*REAL(3*NAT0)/MB
      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6650)DSTORAGE,STORAGE
      ALLOCATE(DCXB(3,NAT0))

      STORAGE=STORAGE+DSTORAGE
      WRITE(0,6655)DSTORAGE,STORAGE
      ALLOCATE(DCXE(3,NAT0))

! Check target dimensions

!*** diagnostic
!      write(0,*)'ddfield ckpt 4, nat0=',nat0
!      write(0,*)' ja  jx  jy  jz'
!      do ja=1,nat0
!         write(0,9711)ja,ixyz0(ja,1),ixyz0(ja,2),ixyz0(ja,3)
!      enddo
! 9711 format(i6,3i4)
!*** end diagnostic

      JXMIN=IXYZ0(1,1)
      JYMIN=IXYZ0(1,2)
      JZMIN=IXYZ0(1,3)
      JXMAX=JXMIN
      JYMAX=JYMIN
      JZMAX=JZMIN
      DO JA=2,NAT0
         JX=IXYZ0(JA,1)
         JY=IXYZ0(JA,2)
         JZ=IXYZ0(JA,3)
         IF(JX.LT.JXMIN)JXMIN=JX
         IF(JX.GT.JXMAX)JXMAX=JX
         IF(JY.LT.JYMIN)JYMIN=JY
         IF(JY.GT.JYMAX)JYMAX=JY
         IF(JZ.LT.JZMIN)JZMIN=JZ
         IF(JZ.GT.JZMAX)JZMAX=JZ
      ENDDO

      AKD2=0.
      DO JD=1,3
         AKD2=AKD2+AKD(JD)**2
      ENDDO
      KD=SQRT(AKD2)

! KD = k*d

      DXPHYS=KD*WAVE/(2._WP*PI)

! Evaluate extreme dipole locations in physical units
! 2009.07.08 (BTD) corrected typo (reported by Shuzhou Li) in following line:
!      XMIN=(REAL(JXMIN)*XX0(1)-0.5_WP)
      XMIN=(REAL(JXMIN)+XX0(1)-0.5_WP)
!-------------------------------------
      XMAX=(REAL(JXMAX)+XX0(1)+0.5_WP)
      YMIN=(REAL(JYMIN)+XX0(2)-0.5_WP)
      YMAX=(REAL(JYMAX)+XX0(2)+0.5_WP)
      ZMIN=(REAL(JZMIN)+XX0(3)-0.5_WP)
      ZMAX=(REAL(JZMAX)+XX0(3)+0.5_WP)

      XMINPHYS=XMIN*DXPHYS*DX(1)
      XMAXPHYS=XMAX*DXPHYS*DX(1)
      YMINPHYS=YMIN*DXPHYS*DX(2)
      YMAXPHYS=YMAX*DXPHYS*DX(2)
      ZMINPHYS=ZMIN*DXPHYS*DX(3)
      ZMAXPHYS=ZMAX*DXPHYS*DX(3)

      WRITE(0,9030)XMIN,XMAX,YMIN,YMAX,ZMIN,ZMAX,                      &
                   XMINPHYS,XMAXPHYS,YMINPHYS,YMAXPHYS,ZMINPHYS,ZMAXPHYS

! Calculate incident B field at origin in TF:

      CXB0(1)=(AKD(2)*CXE0(3)-AKD(3)*CXE0(2))/KD
      CXB0(2)=(AKD(3)*CXE0(1)-AKD(1)*CXE0(3))/KD
      CXB0(3)=(AKD(1)*CXE0(2)-AKD(2)*CXE0(1))/KD

      WRITE(0,7001)NAT0,JXMIN,JXMAX,JYMIN,JYMAX,JZMIN,JZMAX, &
                   XMIN,XMAX,YMIN,YMAX,ZMIN,ZMAX,            &
                   XMINPHYS,XMAXPHYS,YMINPHYS,YMAXPHYS,      &
                   ZMINPHYS,ZMAXPHYS,DXPHYS,PYD,PZD,         &
                   (PYD*DXPHYS*DX(2)),(PZD*DXPHYS*DX(3)),    &
                   WAVE,AKD,GAMMA
      WRITE(0,7002)CXE0
      WRITE(7,7001)NAT0,JXMIN,JXMAX,JYMIN,JYMAX,JZMIN,JZMAX, &
                   XMIN,XMAX,YMIN,YMAX,ZMIN,ZMAX,            &
                   XMINPHYS,XMAXPHYS,YMINPHYS,YMAXPHYS,      &
                   ZMINPHYS,ZMAXPHYS,DXPHYS,PYD,PZD,         &
                   (PYD*DXPHYS*DX(2)),(PZD*DXPHYS*DX(3)),    &
                   WAVE,AKD,GAMMA
      WRITE(7,7002)CXE0
      WRITE(8,7001)NAT0,JXMIN,JXMAX,JYMIN,JYMAX,JZMIN,JZMAX, &
                   XMIN,XMAX,YMIN,YMAX,ZMIN,ZMAX,            &
                   XMINPHYS,XMAXPHYS,YMINPHYS,YMAXPHYS,      &
                   ZMINPHYS,ZMAXPHYS,DXPHYS,PYD,PZD,         &
                   (PYD*DXPHYS*DX(2)),(PZD*DXPHYS*DX(3)),    &
                   WAVE,AKD,GAMMA
      WRITE(8,8002)CXB0

! Calculate range in JY and JZ required for convergence if PBC is used.

      PYDDX=PYD*DX(2)
      PZDDX=PZD*DX(3)
      GAMMAKD4=(GAMMA*GAMMA*AKD2)**2
      RANGE=2./(GAMMAKD4**0.25_WP)
      RANGE2=RANGE*RANGE
      IF(PYDDX.LE.0._WP)THEN
         JPYM=0
      ELSE
         JPYM=1+NINT(RANGE/PYDDX)
      ENDIF
      NPT=0
! 1000 READ(3,*,END=9000,ERR=9000)X(1),X(2),X(3)
 1000 READ(3,*,END=9000,ERR=9000)XA,YA,ZA,XB,YB,ZB,NAB

! evaluate E and B at NAB pts running from (XA,YA,ZA) to (XB,YB,ZB)

      DO JPT=1,NAB ! begin loop over JPT
         IF(NAB.EQ.1)THEN
            X(1)=0.5_WP*(XA+XB)
            X(2)=0.5_WP*(YA+YB)
            X(3)=0.5_WP*(ZA+ZB)
         ELSE
            X(1)=XA+(JPT-1)*(XB-XA)/(NAB-1)
            X(2)=YA+(JPT-1)*(YB-YA)/(NAB-1)
            X(3)=ZA+(JPT-1)*(ZB-ZA)/(NAB-1)
         ENDIF
         NPT=NPT+1

! diagnostic
!         WRITE(0,6100)X
!

! Compute E and B fields at X
! DCXB(JD,JA) = component JD of B field at X 
!               contributed by dipole JA (and replicas).
! DCXE(JD,JA) = component JD of E field at X 
!               contributed by dipole JA (and replicas).

!*** diagnostic
!      write(0,*)'ddfield ckpt 5'
!***
         DO JA=1,NAT0
            DO JD=1,3
               DCXB(JD,JA)=0._WP
               DCXE(JD,JA)=0._WP
            ENDDO
         ENDDO

!*** diagnostic
!      write(0,*)'ddfield ckpt 6'
!***

         PHASY1=AKD(2)*PYDDX
         PHASZ1=AKD(3)*PZDDX

         JAT=0

! parallelize summation over replicas

#ifdef openmp

         IF(NPT.EQ.1)THEN
            NTHREADS=4
            WRITE(0,*)'ddfield ckpt 4, ',                              &
                      'call OMP_SET_NUM_THREADS with NTHREADS=',NTHREADS 
            CALL OMP_SET_NUM_THREADS(NTHREADS)
         ENDIF

!$omp parallel do                                              &
!$omp&   private(jd,jpy,jpz,jpzm)                              &
!$omp&   private(dr,fac,kdr,phasy,phasyz,r,r2,rhat,rjpy,x0,x2,x2y2,y0,z0)  &
!$omp&   private(cxfac,cxfacb,cxfacr,cxp,cxpdot,cxtrm)
         
#endif

         DO JA=1,NAT0

#ifdef openmp
            IF(JA.EQ.1.AND.NPT.EQ.1)THEN
               NTHREADS=OMP_GET_NUM_THREADS()
               WRITE(0,*)'number of openmp threads=',NTHREADS
            ENDIF
#endif

            X0=X(1)-(REAL(IXYZ0(JA,1))+XX0(1))*DX(1)
            Y0=X(2)-(REAL(IXYZ0(JA,2))+XX0(2))*DX(2)
            Z0=X(3)-(REAL(IXYZ0(JA,3))+XX0(3))*DX(3)

! (X0,Y0,Z0)*d = r - r_j00

            DR(1)=X0
            X2=X0**2

! calculate E and B at location r

            DO JD=1,3
               CXP(JD)=CXPOL(JA,JD)
            ENDDO

!*** diagnostic
!      write(0,*)'ddfield ckpt 7'
!***

            DO JPY=-JPYM,JPYM

               PHASY=PHASY1*REAL(JPY)
               RJPY=REAL(JPY)*PYDDX
               IF(PZD.LE.0._WP)THEN
                  JPZM=0
               ELSE
                  JPZM=1+NINT(SQRT(MAX(RANGE2-RJPY**2,0._WP))/PZDDX)
               ENDIF
               DR(2)=Y0-REAL(JPY)*PYDDX
               X2Y2=X2+DR(2)**2
               DO JPZ=-JPZM,JPZM
                  PHASYZ=PHASY+PHASZ1*REAL(JPZ)
                  DR(3)=Z0-REAL(JPZ)*PZDDX
                  R2=X2Y2+DR(3)**2
                  IF(R2.LT.1.E-10_WP)THEN
                     JAT=JA
                  ELSE
                     R=SQRT(R2)
                     R4=R2*R2
                     FAC=EXP(-GAMMAKD4*R4)
                     IF(R.LT.1._WP)FAC=FAC*R4
                     KDR=KD*R

! compute RHAT = (r - r_ja)/|r-r_ja|
! compute CXPDOT = P_ja dot rhat

                     CXPDOT=0.
                     DO JD=1,3
                        RHAT(JD)=DR(JD)/R
                        CXPDOT=CXPDOT+CXP(JD)*RHAT(JD)
                     ENDDO
                     CXFAC=FAC*EXP(CXI*(KDR+PHASYZ))
                     CXFACR=CXFAC/R
                     CXTRM=(CXI*KDR-1._WP)/KDR**2
                     CXFACB=CXFAC*CXTRM

! compute DCXE(JD,JA) = component JD of E field contributed by dipole JA

                     DO JD=1,3
                        DCXE(JD,JA)=DCXE(JD,JA)+                         &
                                    CXFACR*(CXP(JD)-RHAT(JD)*CXPDOT+     &
                                    CXTRM*(CXP(JD)-3._WP*RHAT(JD)*CXPDOT))
                     ENDDO
                     DCXB(1,JA)=DCXB(1,JA)+                          &
                                CXFACB*(CXP(2)*RHAT(3)-CXP(3)*RHAT(2))
                     DCXB(2,JA)=DCXB(2,JA)+                          &
                                CXFACB*(CXP(3)*RHAT(1)-CXP(1)*RHAT(3))
                     DCXB(3,JA)=DCXB(3,JA)+                          &
                                CXFACB*(CXP(1)*RHAT(2)-CXP(2)*RHAT(1))

                  ENDIF   ! endif(r2.lt.1e-10)
               ENDDO   ! enddo jpz=-jpzm,jpzm
            ENDDO   ! enddo jpy=-jpym,jpzm
         ENDDO   ! enddo ja=1,nat0

#ifdef openmp
!$omp end parallel do
#endif

!*** diagnostic
!      write(0,*)'ddfield ckpt 8'
!***

         DO JD=1,3
            CXB(JD)=0._WP
            CXE(JD)=0._WP
         ENDDO

!!NEW STUFF NWB 2_28_12

         !New incident E-field
         
         !Use E-field from fast electron instead. From the included code, X(j), j =1,3 is the
         !position at which the field is to be calculated (assumed from AKD.X in the commented
         !original code above). Using this definition, code from evale.f90 may be incorporated.
         
         !** Calculate center in dipole spacing

         !INCIDENT FIELD COMMENTED OUT -- COMMENT IN TO LOWER BOUND FOR INCIDENT FIELD 

!         PRINT *, 'The beam is at:', Center(1), Center(2), Center(3)
!         PRINT *, 'The dipole spacings are:', DX(1), DX(2), DX(3)
!         PRINT *, 'Wavelength:', WAVE

         !*** Calculate dipole spacing
!         DS = 1E-9_WP

         !*** Calculate omega
!         omega = 2._WP * PI * c / (WAVE * 1E-6_WP)
!         PRINT *, 'omega:', omega
         
         !*** Fast electron E-field
!         gamma_tmp = (1._WP - (velocity / c)**2._WP)**(-0.5_WP)
!         EFieldConstant = 2._WP * e_charge * omega / (velocity**2._WP * gamma_tmp &
!                          * DielectricConst)
!         PRINT *, 'EFieldConstant:', EFieldConstant

         !*** Calculate Radius
!         Radius = (X(1) - Center(1))**2._WP + &
!                  (X(2) - Center(2))**2._WP
!         Radius = SQRT(Radius) * DS
!         PRINT *, 'X1*DX1:', X(1) * DS
!         PRINT *, 'X2*DX2:', X(2) * DS
!         PRINT *, 'Center1:', Center(1)
!         PRINT *, 'Center2:', Center(2)
!         PRINT *, 'CXE is being calculated at point:', X(1) * DS, X(2) * DS, X(3) * DS
!         PRINT *, 'Radius:', Radius

         !** Calculate g(r)
!         BesselArg = omega * Radius / (velocity * gamma_tmp) !The argument of the Bessel functions
!         PRINT *, 'Besselarg:', BesselArg
!         PRINT *, 'Radius post besselarg is:', Radius

         !*** Calculate E-field
!         CXE(1) = EXP(CXI * omega * ( X(3) - Center(3)) * DS / velocity) ! This is the prefactor that each component of CXE is multiplied by
!         PRINT *, 'The prefactor:', CXE(1)
!         CXE(3) = EFieldConstant * CXE(1) * (CXI * besselk0(BesselArg) / gamma_tmp)
!         CXE(2) = EFieldConstant * CXE(1) * (-1._WP * besselk1(BesselArg)) * &
!             DSIN(ATAN2( (X(2) - Center(2)) * DS, (X(1) - Center(1)) * DS))
!         CXE(1) = EFieldConstant * CXE(1) * (-1._WP * besselk1(BesselArg)) * &
!             DCOS(ATAN2( (X(2) - Center(2)) * DS, (X(1) - Center(1)) * DS))
         !LOWER BOUND
!         PRINT *, 'CXE(1):', CXE(1)
!         PRINT *, 'CXE(2):', CXE(2)
!         PRINT *, 'CXE(3);', CXE(3)
!         PRINT *,

!! END NEW STUFF -- NWB

         !Add E-field from dipoles
         !For scattered field only calculations!
         DO JD=1,3
            CXB(JD) = 0._WP
            CXE(JD) = 0._WP
         ENDDO

         DO JA=1,NAT0
            DO JD=1,3
               CXB(JD)=CXB(JD) + DCXB(JD,JA) * CXI * KD**3._WP !multiplication by CXI*KD**3._WP moved from 4 lines down to here by NWB 2_28_12
               CXE(JD) = CXE(JD) + DCXE(JD, JA) * (KD**2._WP) !multiplication by KD**2.0d0 moved from 4 lines down to here by NWB 2_28_12
            ENDDO
         ENDDO
         !DO JD=1,3
            !CXE(JD)=CXE(JD)*KD**2 !Commented out by NWB 2_28_12
            !CXB(JD)=CXB(JD)*CXI*KD**3 !Commented out by NWB 7_15_13
         !ENDDO

! add incident E and B fields
         !Incident E-field for a plane wave
         !NWB :: KDR=AKD(1)*X(1)+AKD(2)*X(2)+AKD(3)*X(3)
         !NWB :: CXFAC=EXP(CXI*KDR)

         !DO JD=1,3
            !Incident E-field for a plane wave
            !CXE(JD)=CXE(JD)+CXE0(JD)*CXFAC  !COMMENTED OUT BY NWB 2/28/12 for testing purposes
            !CXB(JD)=CXB(JD)+CXB0(JD)*CXFAC !Commented out by NWB 7_15_13
         !ENDDO

! under most conditions, the components of E will have magnitudes
! < 10, and the formatting provided by statement 7100 will assure that
! the numbers in the output will be separated by whitespace
! In the unusual event that the components of E become large enough
! (and negative) that whitespace is will be missing between one or more
! of the output columns, instead use statement 7110

! determine formatting requirements for X
! IXDGT = number of spaces to left of decimal point
!      IXDGT=3
!      IF(X(1)<0._WP
! changes yet to be made
!
!         IF(X(1)>-100._WP.AND.X(2)>-100._WP.AND.X(3)>-100._WP)THEN
!            IF(REAL(CXE(1))> -10._WP.AND.IMAG(CXE(1))>-10._WP.AND. &
!               REAL(CXE(2))> -10._WP.AND.IMAG(CXE(2))>-10._WP.AND. &
!               REAL(CXE(3))> -10._WP.AND.IMAG(CXE(3))>-10._WP)THEN
!               WRITE(0,7100)X,CXE 
!               WRITE(7,7100)X,CXE
!            ELSE
!               WRITE(0,7110)X,CXE
!               WRITE(7,7110)X,CXE
!            ENDIF
!            IF(REAL(CXB(1))>-10._WP.AND.IMAG(CXB(1))>-10._WP.AND. &
!               REAL(CXB(2))>-10._WP.AND.IMAG(CXB(2))>-10._WP.AND. &
!               REAL(CXB(3))>-10._WP.AND.IMAG(CXB(3))>-10._WP)THEN
!               WRITE(8,7100)X,CXB
!            ELSE
!               WRITE(8,7100)X,CXB
!            ENDIF
!         ELSE
!            IF(REAL(CXE(1))>-10._WP.AND.IMAG(CXE(1))>-10._WP.AND. &
!               REAL(CXE(2))>-10._WP.AND.IMAG(CXE(2))>-10._WP.AND. &
!               REAL(CXE(3))>-10._WP.AND.IMAG(CXE(3))>-10._WP)THEN
!               WRITE(0,7102)X,CXE
!               WRITE(7,7102)X,CXE
!            ELSE
!               WRITE(0,7112)X,CXE
!               WRITE(7,7112)X,CXE
!            ENDIF
!            IF(REAL(CXB(1))>-10._WP.AND.IMAG(CXB(1))>-10._WP.AND. &
!               REAL(CXB(2))>-10._WP.AND.IMAG(CXB(2))>-10._WP.AND. &
!               REAL(CXB(3))>-10._WP.AND.IMAG(CXB(3))>-10._WP)THEN
!               WRITE(8,7102)X,CXB
!            ELSE
!               WRITE(8,7112)X,CXB
!            ENDIF
!         ENDIF

!This is a revised version of the above original code altered by AV 3.2.2012
               WRITE(0,7114)X,CXE
               WRITE(7,7114)X,CXE
               WRITE(8,7114)X,CXB
!End alterations

!-----------------------------------------------------------------------
         IF(JAT.GT.0)THEN
            DO JD=1,3
               DCXE(JD,JAT)=CXPOL(JAT,JD)*CXADIA(JAT,JD)-CXE(JD)
            ENDDO
             
            ! WRITE(0,7900)DCXE(1,1),DCXE(2,1),DCXE(3,1) !Screen output commented out by NWB 03/07/13
         ENDIF
      ENDDO ! end loop over JPT
      GOTO 1000
!-----------------------------------------------------------------------
 9000 CLOSE(7)
      STOP
 6100 FORMAT(3F9.4)
 6605 FORMAT('allocating',F8.3,' MB for ICOMP ; total=',F10.3,' MB')
 6610 FORMAT('allocating',F8.3,' MB for IXYZ0 ; total=',F10.3,' MB')
 6620 FORMAT('allocating',F8.3,' MB for CXADIA; total=',F10.3,' MB')
 6630 FORMAT('allocating',F8.3,' MB for CXAOFF; total=',F10.3,' MB')
 6640 FORMAT('allocating',F8.3,' MB for CXPOL ; total=',F10.3,' MB')
 6650 FORMAT('allocating',F8.3,' MB for DCXB  ; total=',F10.3,' MB')
 6655 FORMAT('allocating',F8.3,' MB for DCXE  ; total=',F10.3,' MB')
 6660 FORMAT('allocating',F8.3,' MB for BETADF; total=',F10.3,' MB')
 6670 FORMAT('allocating',F8.3,' MB for THETADF;total=',F10.3,' MB')
 6680 FORMAT('allocating',F8.3,' MB for PHIDF;  total=',F10.3,' MB')
 7001 FORMAT(I10,' = number of dipoles in Target',/,                 &
             'Extent of occupied lattice sites',/,                   &
             2I8,' = JXMIN,JXMAX',/,                                 &
             2I8,' = JYMIN,JYMAX',/,                                 &
             2I8,' = JZMIN,JZMAX',/,                                 &
             2F12.6,' = (x_TF/d)min,(x_TF/d)max',/,                  &
             2F12.6,' = (y_TF/d)min,(y_TF/d)max',/,                  &
             2F12.6,' = (z_TF/d)min,(z_TF/d)max',/,                  &
             2F12.6,' = xmin(TF),xmax(TF) (phys. units)',/,          &
             2F12.6,' = ymin(TF),ymax(TF) (phys. units)',/,          &
             2F12.6,' = zmin(TF),zmax(TF) (phys. units)',/,          &
             F12.6,' = d (phys units)',/,                            &
             2F12.6,' = PYD,PZD = period_y/dy, period_z/dz',/,       &
             2F12.6,' = period_y, period_z (phys. units)',/,         &  
             F12.6,' = wavelength in ambient medium (phys units)',/, &
             F12.6,' = k_x*d for incident wave',/,                   &
             F12.6,' = k_y*d for incident wave',/,                   &
             F12.6,' = k_z*d for incident wave',/,                   &
             1PE10.3,' = gamma (parameter for summation cutoff)')
 7002 FORMAT(0PF10.6,0PF10.6,' = (Re,Im)E_inc,x(0,0,0)',/,             &
             0PF10.6,0PF10.6,' = (Re,Im)E_inc,y(0,0,0)',/,             &
             0PF10.6,0PF10.6,' = (Re,Im)E_inc,z(0,0,0)',/,             &
             4X,'x/d',6X,'y/d',6X,'z/d',5X,'----- E_x -----',          &
             3X,'----- E_y ------',3X,'----- E_z -----')
 7100 FORMAT(3F9.4,      &
             F9.5,F9.5,  &
             F10.5,F9.5, &
             F10.5,F9.5)
 7102 FORMAT(3F9.3,      &
             F9.5,F9.5,  &
             F10.5,F9.5, &
             F10.5,F9.5)
 7110 FORMAT(3F9.4,      &
             F9.4,F9.4,  &
             F10.4,F9.4, &
             F10.4,F9.4)
 7112 FORMAT(3F9.3,      &
             F9.4,F9.4,  &
             F10.4,F9.4, &
             F10.4,F9.4)
 7113 FORMAT(3F18.8,      &
             F18.5,F18.5,  &
             F20.5,F18.5, &
             F20.5,F18.5)
!7114 FORMAT(3F18.8,      &
!             F24.16,F24.16,  &
!             F24.16,F24.16, &
!             F24.16,F24.16)
7114 FORMAT(3F18.8,        &
             E20.8e3,E20.10e3, &
             E24.8e3,E24.10e3, &
             E24.8e3,E24.10e3)   
7900 FORMAT('  err(E_x)=(',F10.5,',',F10.5,') ', &
               'err(E_y)=(',F10.5,',',F10.5,') ', &
               'err(E_z)=(',F10.5,',',F10.5,')')
 8002 FORMAT(0PF10.6,0PF10.6,' = (Re,Im)B_inc,x(0,0,0)',/,                 &
             0PF10.6,0PF10.6,' = (Re,Im)B_inc,y(0,0,0)',/,                 &
             0PF10.6,0PF10.6,' = (Re,Im)B_inc,z(0,0,0)',/,                 &
             4X,'x/d',6X,'y/d',6X,'z/d',5X,'----- B_x -----',              &
             3X,'----- B_y ------',3X,'----- B_z -----')
 9030 FORMAT('---------- physical extent in TF of target volume ---------',/, &
             2F14.6,' = (x_TF/d)min, (x_TF/d)max',/,                          &
             2F14.6,' = (y_TF/d)min, (y_TF/d)max',/,                          &
             2F14.6,' = (z_TF/d)min, (z_TF/d)max',/,                          &
             2F14.6,' = (x_TF)min,(x_TF)max (physical units)',/,              &
             2F14.6,' = (y_TF)min,(y_TF)max (physical units)',/,              &
             2F14.6,' = (z_TF)min,(z_TF)max (physical units)')
      END PROGRAM DDFIELD
