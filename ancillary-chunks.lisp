(in-package :png-read)

(defgeneric parse-ancillary-chunk (chunk-type chunk-data)
  (:method (chunk-type chunk-data)
    (warn "Unknown ancillary chunk ~a." chunk-type)))

(defun build-transparency-map (png-state)
  (let ((w (width png-state))
	(h (height png-state))
	(ct (colour-type png-state))
	(imd (image-data png-state))
	(transp (transparency png-state)))
   (let ((t-map (make-array (list w h))))
     (iter (for i from 0 below w)
	   (iter (for j from 0 below h)
		 (setf (aref t-map i j)
		       (ecase ct
			 (0 (if (eql (aref imd i j) transp)
				0
				255))
			 (2 (if (every #'identity
				       ;strange... SBCL hangs during compilation when
				       ;           always iterate keyword is used
				       (iter (for k from 0 to 2)
					     (collect (eql (aref imd i j k)
							   (aref transp k)))))
				0
				255))))))
     (setf (transparency png-state) t-map))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|tRNS|)) chunk-data)
  (ecase (colour-type *png-state*)
    (0 (setf (transparency *png-state*)
	     (big-endian-vector-to-integer chunk-data)))
    (2 (setf (transparency *png-state*)
	     (vector (big-endian-vector-to-integer (subseq chunk-data 0 2))
		     (big-endian-vector-to-integer (subseq chunk-data 2 4))
		     (big-endian-vector-to-integer (subseq chunk-data 4 6)))))
    (3 (setf (transparency *png-state*)
	     chunk-data)))
  (when (or (eql (colour-type *png-state*) 0)
	    (eql (colour-type *png-state*) 2))
    (push #'build-transparency-map (postprocess-ancillaries *png-state*))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|gAMA|)) chunk-data)
  (setf (gamma *png-state*)
	(big-endian-vector-to-integer chunk-data)))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|sBIT|)) chunk-data)
  (setf (significant-bits *png-state*)
	(ecase (colour-type *png-state*)
	  (0 (list :greyscale (aref chunk-data 0)))
	  ((2 3) (list :red (aref chunk-data 0)
		       :green (aref chunk-data 1)
		       :blue (aref chunk-data 2)))
	  (4 (list :greyscale (aref chunk-data 0)
		   :alpha (aref chunk-data 1)))
	  (6 (list :red (aref chunk-data 0)
		   :green (aref chunk-data 1)
		   :blue (aref chunk-data 2)
		   :alpha (aref chunk-data 3))))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|sRGB|)) chunk-data)
  (setf (rendering-intent *png-state*)
	(ecase chunk-data
	  (0 :perceptual)
	  (1 :relative-colorimetric)
	  (2 :saturation)
	  (3 :absolute-colorimetric))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|tEXt|)) chunk-data)
  (let ((separator (position 0 chunk-data)))
    (let ((keyw (octets-to-string chunk-data :end separator :encoding :iso-8859-1))
	  (text-string (octets-to-string chunk-data :start separator :encoding :iso-8859-1)))
      (push (cons keyw text-string) (textual-data *png-state*)))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|zTXt|)) chunk-data)
  (let ((separator (position 0 chunk-data)))
    (let ((keyw (octets-to-string chunk-data :end separator :encoding :iso-8859-1))
	  (compression-method (aref chunk-data (1+ separator))))
      (if (not (zerop compression-method))
	  (cerror "Ignore this zTXt chunk." "Unknown text compression method in zTXt chunk.")
	  (let ((text-string (octets-to-string
			      (decompress nil :zlib chunk-data :input-start (+ separator 2))
			      :encoding :iso-8859-1)))
	    (push (cons keyw text-string) (textual-data *png-state*)))))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|iTXt|)) chunk-data)
  (let ((separator (position 0 chunk-data)))
    (let ((keyw (octets-to-string chunk-data :end separator :encoding :iso-8859-1))
	  (compression-flag (aref chunk-data (1+ separator)))
	  (compression-method (aref chunk-data (+ separator 2)))
	  (separator-2 (position 0 chunk-data :start (1+ separator))))
      (if (and (eql compression-flag 1)
	       (not (zerop compression-method)))
	  (cerror "Ignore this iTXt chunk." "Unknown text compression method in iTXt chunk.")
	  (let ((language-tag (octets-to-string chunk-data :start (+ separator 3)
							   :end separator-2 :encoding :ascii))
		(separator-3 (position 0 chunk-data :start (1+ separator-2))))
	    (let ((tkeyw (octets-to-string chunk-data :start (1+ separator-2)
						      :end separator-3 :encoding :utf-8))
		  (ttext (if (and (eql compression-flag 1)
				  (zerop compression-method))
			     (octets-to-string (decompress nil :zlib chunk-data :input-start (1+ separator-3))
					       :encoding :utf-8)
			     (octets-to-string chunk-data :start (1+ separator-3) :encoding :utf-8))))
	      (push (list keyw language-tag tkeyw ttext) (textual-data *png-state*))))))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|bKGD|)) chunk-data)
  (setf (preferred-background *png-state*)
   (ecase (colour-type *png-state*)
     ((0 4) (big-endian-vector-to-integer chunk-data))
     ((2 6) (vector (big-endian-vector-to-integer (subseq chunk-data 0 2))
		    (big-endian-vector-to-integer (subseq chunk-data 2 4))
		    (big-endian-vector-to-integer (subseq chunk-data 4 6))))
     (3 (aref chunk-data 0)))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|hIST|)) chunk-data)
  (setf (image-histogram *png-state*)
	(coerce (iter (for k index-of-vector chunk-data by 2)
		      (collect (+ (* (aref chunk-data k) 256)
				  (aref chunk-data (1+ k)))))
		'(vector (unsigned-byte 16)))))

(defmethod parse-ancillary-chunk ((chunk-type (eql '|pHYs|)) chunk-data)
  (setf (physical-dimensions *png-state*)
	(list :x-axis (big-endian-vector-to-integer (subseq chunk-data 0 4))
	      :y-axis (big-endian-vector-to-integer (subseq chunk-data 4 8))
	      :unit (ecase (aref chunk-data 8)
		      (0 :unknown)
		      (1 :metre)))))
