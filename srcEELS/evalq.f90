!*************************Alex Vaschillo and Nicholas Bigelow 2012*************************  
!Modified to output the parameter Gamma as described in:
!"Optical Excitations in electron microscopy", Rev. Mod. Phys. v. 82 p. 234 equation (46)
!using the original code for extinction. Normalized to units of /per eV
    SUBROUTINE EVALQ(NAT3,CXE,CXP,CABS,CEXT,CPHA,IMETHD,MXN3,h_bar,h_bar2,MXRAD,AEFFA, &
                     NAT0,c,MXWAV,WAVEA)
     !All arguments h_bar and after added, some arguments removed by NWB 7/11/12
      USE DDPRECISION,ONLY: WP
      IMPLICIT NONE

!*** Arguments:
      INTEGER :: IMETHD, MXN3, NAT3, NAT0, MXRAD, MXWAV
      REAL(WP) :: CABS, CEXT, CPHA, h_bar, h_bar2, AEFFA(MXRAD), AK(3), &
                  c, WAVEA(MXWAV)
      COMPLEX(WP) :: CXE(MXN3), CXP(MXN3)

!*** Local variables:
      COMPLEX(WP) :: CXA, CXI, DCXA, RABS, POL(3)
      REAL(WP) :: PI, DS, omega
      INTEGER :: J1, J2, J3, NAT

!*** Intrinsic functions:
      INTRINSIC AIMAG, CONJG, REAL, SQRT

!*** SAVE statements:
      SAVE CXI

!*** Data statements:
      DATA CXI/(0._WP,1._WP)/

!***********************************************************************

! Given: NAT3 = 3*number of dipoles
!        CXE(1-NAT3) = components of E field at each dipole, in order
!                      E_1x,E_2x,...,E_NATx,E_1y,E_2y,...,E_NATy,
!                      E_1z,E_2z,...,E_NATz
!        CXP(1-NAT3) = components of polarization vector at each dipole,
!                      in order
!                      P_1x,P_2x,...,P_NATx,P_1y,P_2y,...,P_NATy,
!                      P_1z,P_2z,...,P_NATz
!        IMETHD = 0 or 1
! Finds:
!        CEXT = loss probability, Gamma, in units of eV^-1
!  and, if IMETHD=1, also computes
!        CPHA = 0
!        CABS = 0
!Inputs and outputs updated by NWB, 7/11/12

! B.T.Draine, Princeton Univ. Obs., 87/1/4

! History:
! 88.04.28 (BTD): modifications
! 90.11.02 (BTD): modified to allow use of vacuum sites (now pass E02
!                 from calling routine instead of evaluating it here)
! 90.12.13 (BTD): modified to use IMETHD flag, to allow "fast" calls
!                 in which only CEXT is computed.
! 97.12.26 (BTD): removed CXALPH from argument list; replaced with
!                 CXADIA and CXAOFF.
!                 CXADIA and CXAOFF are diagonal and off-diagonal
!                 elements of alpha^{-1} for each dipole.
!                 Modified to properly evaluate CABS
! 98.01.01 (BTD): Correct inconsistencies in assumed data ordering.
! 98.01.13 (BTD): Examine for possible error in evaluation of Qabs
! 98.04.27 (BTD): Minor polishing.
! 08.01.13 (BTD): cosmetic changes to f90 version
! End history

! Copyright (C) 1993,1997,1998,2008 B.T. Draine and P.J. Flatau
! This code is covered by the GNU General Public License.
!***********************************************************************

      !Zero out variables and define internal constants
      CEXT = 0._WP
      CABS = 0._WP
      CPHA = 0._WP
      CXA = 0._WP
      PI = 4._WP * ATAN(1._WP) !Pi

!*** Compute dipole spacing in meters
      DS = 1E-6_WP * AEFFA(1) * (4._WP * PI / (3._WP * NAT0) )**(1._WP/3._WP)

      IF ( IMETHD==0 ) THEN

         !*** Compute CEXT:
         DO J1=1,NAT3
            CEXT = CEXT + AIMAG(CXP(J1)) * REAL(CXE(J1)) - &
            REAL(CXP(J1)) * AIMAG(CXE(J1)) !ORIGINAL CODE, Eapp* dot P
         ENDDO
         
         !Compute Gamma using CEXT NWB 7/11/12
         CEXT = CEXT * ((PI * h_bar * h_bar2) ** (-1._WP)) * 1.E-18_WP !(10^6)^3 correction factor for um/m  

         !Renormalize for dipole spacing
         CEXT = CEXT * (DS * 1.E9_WP)**3._WP

      ELSEIF (IMETHD == 1) THEN

         !*** Compute CEXT:
         DO J1 = 1,3
            POL(J1) = 0
         ENDDO
         DO J1=1,NAT3
            CXA = CXA + CXP(J1) * CONJG(CXE(J1))   !sum(E dot P)
            IF (J1 .LE. NAT3/3) THEN
               POL(1) = POL(1) + CXP(J1)
            ELSEIF (J1 .LE. 2*NAT3/3) THEN
               POL(2) = POL(2) + CXP(J1)
            ELSE
               POL(3) = POL(3) + CXP(J1)
            ENDIF
         ENDDO
         DO J1 = 1,3
            CABS = CABS + POL(J1) * CONJG(POL(J1))
         ENDDO

         !Compute Gamma using CEXT NWB 7/11/12           
         CEXT = AIMAG(CXA) * ((PI * h_bar * h_bar2) ** (-1._WP)) * 1.E-18_WP !(10^6)^3 correction factor for um/m

         !Compute CL
         omega = 2._WP * PI * c / (WAVEA(1) * 1E-6_WP)
         CABS = CABS * 2._WP * (omega**4._WP) / (3._WP * (c**3._WP)) * 1.E-18_WP
         PRINT *,'CABS in EVALQ = ',CABS

         !Renormalize for dipole spacing
         CEXT = CEXT * (DS * 1.E9_WP)**3._WP
         
      ENDIF

      RETURN
    END SUBROUTINE EVALQ
