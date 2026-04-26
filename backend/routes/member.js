const express = require('express');
const router  = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const roleGuard      = require('../middleware/roleGuard');
const {
  getMemberDashboard, getMyComplaints, raiseComplaint,
  getComplaintDetail, getProfile, updateProfile
} = require('../controllers/complaintsController');

router.use(authMiddleware, roleGuard('member'));

router.get('/dashboard',          getMemberDashboard);
router.get('/complaints',         getMyComplaints);
router.post('/complaints',        raiseComplaint);
router.get('/complaints/:id',     getComplaintDetail);
router.get('/profile',            getProfile);
router.put('/profile',            updateProfile);

module.exports = router;
