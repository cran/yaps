#' Simulate a known movement track for subsequent estimation using YAPS
#'
#' Produces a simulated regular time-spaced track following the specified movement model. Linear movement between consecutive observations is assumed.
#' The output contains x, y, time and sound speed at each simulated position.
#'
#' @param model Movement model: 'rw': Two-dimension random walk  (X,Y)
#' @param n Number of steps in the simulated track 
#' @param deltaTime Number of time units (seconds) between each location
#' @param D Diffusivity of the animal movement - only used if model='rw'
#' @param shape Shape of the Weibull distribution - only used when model='crw'. 
#' @param scale Scale of the Weibull distribution - only used when model='crw'. 
#' @param addDielPattern Adds a realistic(?) diel pattern to movement. Periods of both low and high movement
#' @param start_pos Specify the starting position of the track with c(x0, y0)
#' @param ss Simulations model for Speed of Sound - defaults to 'rw' = RW-model.
#'
#' @return `data.frame` containing a simulated track
#' @export
#' @example man/examples/example-yaps_sim.R
simTrueTrack <- function(model='rw', n, deltaTime=1, D=NULL, shape=NULL, scale=NULL, addDielPattern=TRUE, ss='rw', start_pos=NULL){
	try(if(model=='rw'  & is.null(D)) stop("When model == 'rw', D needs to be specified"))
	try(if(model=='crw' & (is.null(shape) | is.null(scale))) stop("When model == 'crw', shape and scale needs to be specified"))
	
	#times
	dt <- rep(deltaTime, n-1)
	time <- cumsum(c(0, dt))
	
	#start position
	if(!is.null(start_pos)){
	  x0 <- start_pos[1]
	  y0 <- start_pos[2]
	}	else{
	  x0 <- stats::runif(1,0,5)
	  y0 <- stats::runif(1,0,5)
	}
	
	#RW-model
	if(model == 'rw'){
		x <- cumsum(c(x0, stats::rnorm(n-1, 0, sd=sqrt(2*D*dt))))
		y <- cumsum(c(y0, stats::rnorm(n-1, 0, sd=sqrt(2*D*dt))))
	} else if (model == 'crw'){
		# make weibull distributed steps
		steps <- stats::rweibull(n-1, shape, scale)
		if(addDielPattern){
			# # # # make diel pattern - first 1/4 very little movement, middle half normal-high movement, last 1/4 very little movement
			steps[1:floor(n/8)] <- steps[1:floor(n/8)]/50
			steps[(3*floor(n/8)):(4*floor(n/8))] <- steps[(3*floor(n/8)):(4*floor(n/8))]/50
			steps[(5*floor(n/8)):(6*floor(n/8))] <- steps[(5*floor(n/8)):(6*floor(n/8))]/50
			steps[(7*floor(n/8)):n-1] <- steps[(7*floor(n/8)):n-1]/50
		}
		
		# make clustered turning angles
		theta <- circular::rwrappedcauchy(n-1, mu=circular::circular(0), rho=.99)
		# cumulative angle (absolute orientation)
		Phi <- cumsum(theta)
		# step length components
		dX <- c(x0, steps*cos(Phi))
		dY <- c(y0, steps*sin(Phi))
		# actual X-Y values
		x<-cumsum(dX)
		y<-cumsum(dY)
	}

	if(ss == 'rw'){
		ssD <- stats::rnorm(length(x), 0, 7e-2)
		ss <- 1450 + cumsum(ssD)
	} else if (ss == 'constant'){
		ss <- rep(1450, length(x))
	}

	return(data.table::data.table(time=time, x=x, y=y, ss=ss))
}

#' Simulate telemetry track based on known true track obtained using simTrueTrack
#'
#' Based on a known true track obtained using simTrueTrack, this function will give true positions at time-of-pings, which are also in the output. TOPs are determined by user-specified transmitter type.
#' Number of pings are determined automatically based on track length and transmitter specifications.
#' @param trueTrack Know track obtained using simTrueTrack
#' @param sbi_mean,sbi_sd Mean and SD of burst interval when pingType = 'sbi'
#' @inheritParams getInp
#'
#' @return `data.frame` containing time of ping and true positions
#' @export
#' @example man/examples/example-yaps_sim.R
simTelemetryTrack <- function(trueTrack, pingType, sbi_mean=NULL, sbi_sd=NULL, rbi_min=NULL, rbi_max=NULL){
	if(pingType == 'sbi'){
		top <- simTOP(trueTrack, pingType='sbi', sbi_mean=sbi_mean, sbi_sd=sbi_sd)
	} else if(pingType == 'rbi'){
		top <- simTOP(trueTrack, pingType='rbi', rbi_min=rbi_min, rbi_max=rbi_max)
	} else if(pingType == 'pbi'){
		top_list <- simTOP(trueTrack, pingType='pbi', rbi_min=rbi_min, rbi_max=rbi_max)
		top <- top_list$top
		biTable <- top_list$biTable
	}
	
	x  <- stats::approx(x=trueTrack$time, y=trueTrack$x, xout=top)$y
	y  <- stats::approx(x=trueTrack$time, y=trueTrack$y, xout=top)$y
	ss <- stats::approx(x=trueTrack$time, y=trueTrack$ss, xout=top)$y

	out <- data.frame(top=top, x=x, y=y, ss=ss)

	if(pingType == 'pbi'){
		return(list(out=out, biTable=biTable))
	} else {
		return(out)
	}
}


#' Sim hydrophone array configuration
#'
#' @param auto If TRUE, attempts to find a decent array configuration to cover the simulated true track.
#' @param trueTrack Track obtained from simTrueTrack().
#'
#' @export
#' @return `data.frame` containing X and Y for hydros
#' @example man/examples/example-yaps_sim.R
simHydros <- function(auto=TRUE, trueTrack=NULL){
	try(if(auto == TRUE & is.null(trueTrack)) stop("When auto is TRUE, trueTrack needs to be supplied"))
	hx.min <- min(trueTrack$x) - 25
	hx.max <- max(trueTrack$x) + 25
	hy.min <- min(trueTrack$y) - 25
	hy.max <- max(trueTrack$y) + 25

	hx <- c(hx.min,hx.min,hx.max,hx.max, 0, 500,  500, -500, -500)
	hy <- c(hy.min,hy.max,hy.max,hy.min, 0, 500, -500, -500, 500)

	hydros <- data.table::data.table(hx=hx, hy=hy, hz=1)

	return(hydros)
}

#' Sim TOA matrix for the supplied telemetryTrack
#'
#' Provides the TOA matrix for the specified telemetryTrack. Probability of NA (pNA) and observation noise (sigmaToa) can be specified.
#' @param telemetryTrack Dataframe obtained from simTelemetryTrack
#' @param hydros Dataframe obtained from getHydros
#' @param sigmaToa Detection uncertainty
#' @param pNA Probability of missing detection 0-1
#' @param pMP Probability of multipath propagated signal 0-1
#' @param tempRes Temporal resolution of the hydrophone. PPM systems are typially 1/1000 sec. Other systems are as high as 1/19200 sec.
#' @inheritParams getInp
#'
#' @export
#' @return List containing TOA matrix (toa) and matrix indicating, which obs are multipath (mp_mat)
#' @example man/examples/example-yaps_sim.R
simToa <- function(telemetryTrack, hydros, pingType, sigmaToa, pNA, pMP, tempRes=NA){
	#correct toa
	toa <- apply(telemetryTrack, 1, function(k) k['top'] + sqrt((hydros$hx - k['x'])^2 + (hydros$hy - k['y'])^2 ) / k['ss'])
	
	#add random errors
	toa <- toa + stats::rnorm(length(toa), 0, sigmaToa)
	
	#make temporal resolution pingType specific
	#sbi 1/19200    rbi 1/1000
	if(pingType == 'sbi' & is.na(tempRes)) {	
		tempRes <- 19200
	} else if(pingType == 'rbi' | pingType == 'pbi' & is.na(tempRes)) {
		tempRes <- 1000
	}
	toa <- floor(toa) + cut(toa-floor(toa), breaks=1:tempRes/tempRes, labels=FALSE)/tempRes
	#add random measurement variation in steps of tempRes
	toa <- toa + stats::rpois(length(toa), 1) * sample(c(-1,1), size=length(toa), replace=TRUE) * 1/tempRes
	
	#add NAs
	toa <- toa * stats::rbinom(length(toa),1, (1-pNA))
	toa[which(toa == 0)] <- NA
	
	#add MP
	mp_mat <- matrix(stats::rbinom(length(toa),1, pMP), ncol=ncol(toa))
	toa <- toa + mp_mat * stats::runif(length(toa), 50, 300) / telemetryTrack$ss
	
	return(list(toa=toa, mp_mat=mp_mat))
}



#' Simulate time of pings (Internal function)
#'
#' This function will produce simulated time of pings of the relevant type. For internal use only; should not be needed by users.
#'
#' @param trueTrack Track obtained from simTrueTrack().
#' @inheritParams getInp
#' @inheritParams simTelemetryTrack
#' @return Vector of simulated time of pings. Length = number of steps in simulated track.
#' @noRd
simTOP <- function(trueTrack, pingType, sbi_mean=NULL, sbi_sd=NULL, rbi_min=NULL, rbi_max=NULL){
	maxTime <- max(trueTrack$time)
	top0 <- stats::runif(1,0,0.5)
	# top <- 0
	if(pingType == 'sbi') {
		try(if(is.null(sbi_mean) | is.null(sbi_sd)) stop("When pingType == 'sbi', both sbi_mean and sbi_sd must be specified!", call.=FALSE))
		bi <- stats::rnorm(1, sbi_mean, sbi_sd)
		while(max(cumsum(bi)) < maxTime){
			bi <- c(bi, utils::tail(bi, n=1) + stats::rnorm(1, 0, sbi_sd))
		}
		top <- c(top0, top0+cumsum(bi))
	} else if (pingType == 'rbi'){
		try(if(is.null(rbi_min) | is.null(rbi_max)) stop("When pingType == 'rbi', both rbi_min and rbi_max must be specified!", call.=FALSE))
		top <- top0
		while(max(top) < maxTime){
			top <- c(top, max(top) + stats::runif(1, rbi_min, rbi_max))
		}
	} else if (pingType == 'pbi'){
		try(if(is.null(rbi_min) | is.null(rbi_max)) stop("When pingType == 'pbi', both rbi_min and rbi_max must be specified!", call.=FALSE))
		biTable <- round(stats::runif(256, rbi_min, rbi_max), 1)
		top <- top0
		i <- 1
		while(max(top) < maxTime){
			top <- c(top, max(top) + biTable[i] + round(stats::rnorm(1, 1E-3, 1E-3), digits=5)) # last part introduce a slight directional drift...
			if(i == length(biTable)) {
				i <- 1
			} else {
				i <- i+1
			}
		}
	}
	top <- top[1:length(top)-1]
	if(pingType == 'pbi'){
		if(length(top) > length(biTable)){
			biTable_out <- rep(biTable, times=ceiling(length(top) / length(biTable)))
		} else {biTable_out <- biTable}
		biTable_out <- biTable_out[1:length(top)]
	}
	
	if(pingType == 'pbi'){
		return(list(top=top, biTable=biTable_out))
	} else {	
		return(top)
	}
}

