### Functions to handle seasonality

monthdays <- function(x)
{
    if(!is.ts(x))
        stop("Not a time series")
    f <- frequency(x)
    if(f==12)
        days <- c(31,28,31,30,31,30,31,31,30,31,30,31)
    else if(f==4)
        days <- c(90,91,92,92)
    else
        stop("Not monthly or quarterly data")
    nyears <- round(length(x)/f+1)+1
    years <- (1:nyears) + (start(x)[1] - 1)
    leap.years <- ((years %% 4 == 0) & !(years %% 100 ==0 & years %% 400 != 0))[1:nyears]
    dummy <- t(matrix(rep(days,nyears),nrow=f))
    if(f==12)
        dummy[leap.years,2] <- 29
    else
        dummy[leap.years,1] <- 91
    xx <- c(t(dummy))[start(x)[2]-1+(1:length(x))]
    return(ts(xx,start=start(x),frequency=f))
}

sindexf <- function(object,h)
{
    if(class(object)=="stl")
    {
        ss <- object$time.series[,1]
        m <- frequency(ss)
        ss <- ss[length(ss)-(m:1)+1]
        tsp.x <- tsp(object$time.series)
    }
    else if(class(object)=="decomposed.ts")
    {
        ss <- object$figure
        m <- frequency(object$seasonal)
        n <- length(object$trend)
        ss <- rep(ss,n/m+1)[1:n]
        ss <- ss[n-(m:1)+1]
        tsp.x <- tsp(object$seasonal)
    }
    else
        stop("Object of unknown class")
    out <- ts(rep(ss,h/m+1)[1:h], frequency=m, start=tsp.x[2]+1/m)

    return(out)
}


seasonaldummy <- function(x, h=NULL)
{
  if(!is.ts(x))
    stop("Not a time series")
  else
    fr.x <- frequency(x)
  if(is.null(h)){
    if(fr.x==1)
      stop("Non-seasonal time series")
    dummy <- as.factor(cycle(x))
    dummy.mat <- matrix(0,ncol=frequency(x)-1,nrow=length(x))
    nrow <- 1:length(x)
    for(i in 1:(frequency(x)-1))
      dummy.mat[dummy==paste(i),i] = 1
    colnames(dummy.mat) <- if (fr.x == 12)
      month.abb[1:11]
    else if(fr.x == 4)
      c("Q1", "Q2", "Q3")
    else paste("S",1:(fr.x-1),sep="")

    return(dummy.mat)
  }
  else{
    return(seasonaldummy(ts(rep(0,h),start=tsp(x)[2]+1/fr.x,frequency=fr.x)))
  }
}

seasonaldummyf <- function(x, h)
{
  warning("seasonaldummyf() is deprecated, please use seasonaldummy()")
  if(!is.ts(x))
    stop("Not a time series")
  f <- frequency(x)
  return(seasonaldummy(ts(rep(0,h),start=tsp(x)[2]+1/f,frequency=f)))
}

forecast.stl <- function(object, method=c("ets","arima","naive","rwdrift"), etsmodel="ZZN",
     forecastfunction=NULL,
     h = frequency(object$time.series)*2, level = c(80, 95), fan = FALSE,
     lambda=NULL, biasadj=FALSE, xreg=NULL, newxreg=NULL, allow.multiplicative.trend=FALSE, ...)
{
  method <- match.arg(method)
  if(is.null(forecastfunction))
  {
    if(method!="arima" & (!is.null(xreg) | !is.null(newxreg)))
      stop("xreg and newxreg arguments can only be used with ARIMA models")
    if(method=="ets")
    {
      # Ensure non-seasonal model
      if(substr(etsmodel,3,3) != "N")
      {
        warning("The ETS model must be non-seasonal. I'm ignoring the seasonal component specified.")
        substr(etsmodel,3,3) <- "N"
      }
      forecastfunction <- function(x,h,level,...){
        fit <- ets(x,model=etsmodel, allow.multiplicative.trend=allow.multiplicative.trend, ...)
        return(forecast(fit,h=h,level=level))
      }
    }
    else if(method=="arima")
    {
      forecastfunction <- function(x,h,level,...){
        fit <- auto.arima(x,xreg=xreg,seasonal=FALSE,...)
        return(forecast(fit,h=h,level=level,xreg=newxreg))
      }
    }
    else if(method=="naive")
    {
      forecastfunction <- function(x, h,level,...){
        rwf(x,drift=FALSE,h=h,level=level,...)
      }
    }
    else if(method=="rwdrift")
    {
      forecastfunction <- function(x, h,level,...){
        rwf(x,drift=TRUE,h=h,level=level,...)
      }
    }
  }
  if(is.null(xreg) != is.null(newxreg))
    stop("xreg and newxreg arguments must both be supplied")
  if(!is.null(newxreg))
  {
    if(nrow(as.matrix(newxreg))!=h)
      stop("newxreg should have the same number of rows as the forecast horizon h")
  }
  if(fan)
    level <- seq(51, 99, by = 3)

  m <- frequency(object$time.series)
  n <- nrow(object$time.series)
  lastseas <- rep(object$time.series[n-(m:1)+1,"seasonal"],trunc(1+(h-1)/m))[1:h]
  # De-seasonalize
  x.sa <- seasadj(object)
  # Forecast
  fcast <- forecastfunction(x.sa, h=h, level=level, ...)

  # Reseasonalize
  fcast$mean <- fcast$mean + lastseas
  fcast$upper <- fcast$upper + lastseas
  fcast$lower <- fcast$lower + lastseas
  fcast$x <- ts(rowSums(object$time.series))
  tsp(fcast$x) <- tsp(object$time.series)
  fcast$method <- paste("STL + ",fcast$method)
  fcast$seasonal <- ts(lastseas[1:m],frequency=m,start=tsp(object$time.series)[2]-1+1/m)
  fcast$fitted <- fitted(fcast)+object$time.series[,1]
  fcast$residuals <- fcast$x - fcast$fitted

	if (!is.null(lambda))
	{
		fcast$x <- InvBoxCox(fcast$x,lambda)
		fcast$fitted <- InvBoxCox(fcast$fitted, lambda)
		fcast$mean <- InvBoxCox(fcast$mean, lambda)
		if(biasadj){
		  fcast$mean <- InvBoxCoxf(fcast, lambda = lambda)
		}
		fcast$lower <- InvBoxCox(fcast$lower, lambda)
		fcast$upper <- InvBoxCox(fcast$upper, lambda)
		fcast$lambda <- lambda
	}

   return(fcast)
}


# Function takes time series, does STL decomposition, and fits a model to seasonally adjusted series
# But it does not forecast. Instead, the result can be passed to forecast().
stlm <- function(y ,s.window=7, robust=FALSE, method=c("ets","arima"),
     modelfunction=NULL, etsmodel="ZZN", lambda=NULL, xreg=NULL, allow.multiplicative.trend=FALSE, x=y, ...)
{
  method <- match.arg(method)

  # Transform data if necessary
  origx <- x
  if (!is.null(lambda))
    x <- BoxCox(x, lambda)

  # Do STL decomposition
  stld <- stl(x,s.window=s.window,robust=robust)

  # Construct modelfunction if not passed as an argument
  if(is.null(modelfunction))
  {
    if(method!="arima" & !is.null(xreg))
      stop("xreg arguments can only be used with ARIMA models")
    if(method=="ets")
    {
      # Ensure non-seasonal model
      if(substr(etsmodel,3,3) != "N")
      {
        warning("The ETS model must be non-seasonal. I'm ignoring the seasonal component specified.")
        substr(etsmodel,3,3) <- "N"
      }
      modelfunction <- function(x,...){return(ets(x,model=etsmodel,
        allow.multiplicative.trend=allow.multiplicative.trend,...))}
    }
    else if(method=="arima")
      modelfunction <- function(x,...){return(auto.arima(x,xreg=xreg,seasonal=FALSE,...))}
  }

  # De-seasonalize
  x.sa <- seasadj(stld)

  # Model seasonally adjusted data
  fit <- modelfunction(x.sa, ...)
  fit$x <- x.sa

  # Fitted values and residuals
  fits <- fitted(fit) + stld$time.series[,"seasonal"]
  res <- residuals(fit)

  return(structure(list(stl=stld,model=fit, lambda=lambda, x=origx, m=frequency(origx),
     fitted=fits, residuals=res),class="stlm"))
}

forecast.stlm <- function(object, h = 2*object$m, level = c(80, 95), fan = FALSE,
     lambda=object$lambda, biasadj=FALSE, newxreg=NULL, allow.multiplicative.trend=FALSE, ...)
{
  if(!is.null(newxreg))
  {
    if(nrow(as.matrix(newxreg))!=h)
      stop("newxreg should have the same number of rows as the forecast horizon h")
  }
  if(fan)
    level <- seq(51, 99, by = 3)

  m <- frequency(object$stl$time.series)
  n <- nrow(object$stl$time.series)
  lastseas <- rep(object$stl$time.series[n-(m:1)+1,"seasonal"],trunc(1+(h-1)/m))[1:h]

  # Forecast seasonally adjusted series
  if(is.element("Arima",class(object$model)) & !is.null(newxreg))
    fcast <- forecast(object$model, h=h, level=level, xreg=newxreg, ...)
  else if(is.element("ets",class(object$model)))
    fcast <- forecast(object$model, h=h, level=level,
      allow.multiplicative.trend=allow.multiplicative.trend, ...)
  else
    fcast <- forecast(object$model, h=h, level=level, ...)

  # Reseasonalize
  fcast$mean <- fcast$mean + lastseas
  fcast$upper <- fcast$upper + lastseas
  fcast$lower <- fcast$lower + lastseas
  fcast$method <- paste("STL + ",fcast$method)
  fcast$seasonal <- ts(lastseas[1:m],frequency=m,start=tsp(object$stl$time.series)[2]-1+1/m)
  #fcast$residuals <- residuals()
  fcast$fitted <- fitted(fcast)+object$stl$time.series[,1]

  if (!is.null(lambda))
  {
    fcast$fitted <- InvBoxCox(fcast$fitted, lambda)
    fcast$mean <- InvBoxCox(fcast$mean, lambda)
    if(biasadj){
      fcast$mean <- InvBoxCoxf(fcast, lambda = lambda)
    }
    fcast$lower <- InvBoxCox(fcast$lower, lambda)
    fcast$upper <- InvBoxCox(fcast$upper, lambda)
    fcast$lambda <- lambda
  }
  fcast$x <- object$x

  return(fcast)
}

stlf <- function(y, h=frequency(x)*2, s.window=7, t.window=NULL, robust=FALSE, lambda=NULL, biasadj=FALSE, x=y, ...)
{
	if (!is.null(lambda))
	{
		origx <- x
		x <- BoxCox(x, lambda)
	}

	fit <- stl(x,s.window=s.window,t.window=t.window,robust=robust)
	fcast <- forecast(fit,h=h,lambda=lambda,biasadj=biasadj, ...)

	# if (!is.null(lambda))
	# {
	# 	fcast$x <- origx
	# 	fcast$fitted <- InvBoxCox(fcast$fitted, lambda)
	# 	fcast$mean <- InvBoxCox(fcast$mean, lambda)
	# 	fcast$lower <- InvBoxCox(fcast$lower, lambda)
	# 	fcast$upper <- InvBoxCox(fcast$upper, lambda)
	# 	fcast$lambda <- lambda
	# }

	return(fcast)
}

fourier <- function(x, K, h=NULL)
{
  if(is.null(h)){
    return(...fourier(x, K, 1:length(x)))
  }
  else{
    return(...fourier(x, K, length(x)+(1:h)))
  }
}

fourierf <- function(x, K, h)
{
  warning("fourierf() is deprecated, please use fourier()")
  return(...fourier(x, K, length(x)+(1:h)))
}


# Function to do the work.
...fourier <- function(x, K, times)
{
  if (any(class(x) == "msts")) {
    period <- attr(x, "msts")
  } else {
    period <- frequency(x)
  }

  # Patch for older versions of R that do not have sinpi and cospi functions.
  if(!exists("sinpi"))
  {
    sinpi <- function(x){sin(pi*x)}
    cospi <- function(x){cos(pi*x)}
  }

  len.p <- length(period)
  if(len.p != length(K))
    stop("Number of periods does not match number of orders")
  if(any(2*K > period))
    stop("K must be not be greater than period/2")

  len <- 2*sum(K)
  X <- matrix(0,nrow=length(times),ncol=len)*NA
  labels <- character(length = len) # column names
  cs.K <- cumsum(2*c(0, K))
  for (j in 1:len.p) {
    if(K[j] > 0L) {
      for(i in 1L:K[j]) {
        if(2*i < period[j])
          X[,cs.K[j] + 2*i-1] <- sinpi(2*i*times/period[j])
        X[,cs.K[j] + 2*i] <- cospi(2*i*times/period[j])
      }
      labels[(cs.K[j] + 1):cs.K[j + 1]] <- paste(paste0(c("S","C"),rep(1:K[j],rep(2,K[j]))),
                                               round(period[j]), sep = "-")
    }
  }
  colnames(X) <- labels
  # Remove missing columns
  X <- X[,!is.na(colSums(X))]
  # Remove equal columns
  X <- unique(X, MARGIN=2)

  return(X)
}

ma <- function(x, order, centre=TRUE)
{
  if(abs(order - round(order)) > 1e-8)
    stop("order must be an integer")

  if(order%%2 == 0 & centre) #centred and even
    w <- c(0.5,rep(1,order-1),0.5)/order
  else # odd or not centred
    w <- rep(1,order)/order

  return(filter(x, w))
}

is.stlm <- function(x){
  inherits(x, "stlm")
}
